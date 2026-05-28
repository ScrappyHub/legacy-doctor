# =====================================================================
# PATCH: LD-STORAGE-01 add "inspect" command handler
# Target: scripts\storage\ld_storage_v1.ps1
# Sentinel: LD_STORAGE_INSPECT_V1
# =====================================================================
param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Utf8NoBom(){ New-Object System.Text.UTF8Encoding($false) }
function ReadUtf8([string]$p){ [IO.File]::ReadAllText($p,(Utf8NoBom)) }
function WriteUtf8NoBomLf([string]$path,[string]$text){
  $dir = Split-Path -Parent $path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = ($text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($path,$t,(Utf8NoBom))
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){ throw ("WRITE_FAILED: " + $path) }
}
function ParseGateFile([string]$path){
  $tok=$null; $err=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tok,[ref]$err)
  if($err -and $err.Count -gt 0){
    $e=$err[0]
    throw ("PARSE_GATE_FAIL: {0}:{1}:{2}: {3}" -f $path,$e.Extent.StartLineNumber,$e.Extent.StartColumnNumber,$e.Message)
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Target = Join-Path $RepoRoot "scripts\storage\ld_storage_v1.ps1"
if(-not (Test-Path -LiteralPath $Target -PathType Leaf)){ throw ("MISSING_TARGET: " + $Target) }

$src = ReadUtf8 $Target
$src = ($src -replace "`r`n","`n") -replace "`r","`n"

if($src -match 'LD_STORAGE_INSPECT_V1'){
  Write-Output ("OK: already patched (LD_STORAGE_INSPECT_V1) target=" + $Target)
  exit 0
}

# We insert an inspect branch immediately BEFORE the existing UNKNOWN_CMD/format gate:
#   if($Cmd -ne "format"){ Die ("UNKNOWN_CMD: " + $Cmd) }
$needle = 'if\(\$Cmd\s*-ne\s*"format"\s*\)\s*\{\s*Die\s*\(\s*\("UNKNOWN_CMD:\s*"\s*\+\s*\$Cmd\)\s*\)\s*\}\s*'
$m = [regex]::Match($src, $needle)
if(-not $m.Success){
  throw "PATCH_FAIL: could not locate UNKNOWN_CMD format gate (expected: if($Cmd -ne ""format""){ Die (""UNKNOWN_CMD: "" + $Cmd) })"
}

$insert = @'
# === LD_STORAGE_INSPECT_V1 ===
if($Cmd -eq "inspect"){
  # Purpose: enumerate disks/partitions/volumes even when no drive letter is assigned.
  # Output: stable table; receipts: action=inspect, counts.
  $rows = New-Object System.Collections.Generic.List[object]

  $disks = @(Get-Disk | Sort-Object Number)
  foreach($d in $disks){
    $parts = @()
    try { $parts = @(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue | Sort-Object PartitionNumber) } catch { $parts = @() }

    foreach($p in $parts){
      $dl = ""
      try { if($p.DriveLetter){ $dl = ([string]$p.DriveLetter).ToUpperInvariant() } } catch { $dl = "" }

      $aps = @()
      try { $aps = @(Get-PartitionAccessPath -DiskNumber $d.Number -PartitionNumber $p.PartitionNumber -ErrorAction SilentlyContinue | ForEach-Object { [string]$_.AccessPath }) } catch { $aps = @() }
      $aps2 = @($aps | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object)

      $fs = ""
      $label = ""
      $size = $null
      $free = $null
      $health = ""
      $op = ""
      try {
        if(-not [string]::IsNullOrWhiteSpace($dl)){
          $v = Get-Volume -DriveLetter $dl -ErrorAction Stop
          $fs = [string]$v.FileSystem
          $label = [string]$v.FileSystemLabel
          $size = $v.Size
          $free = $v.SizeRemaining
          $health = [string]$v.HealthStatus
          $op = [string]$v.OperationalStatus
        }
      } catch { }

      $row = [pscustomobject]@{
        DiskNumber      = $d.Number
        DeviceId        = (MakeDeviceId $d)
        BusType         = ([string]$d.BusType)
        DiskSizeBytes   = $d.Size
        PartitionStyle  = ([string]$d.PartitionStyle)

        PartitionNumber = $p.PartitionNumber
        DriveLetter     = $dl
        AccessPaths     = (@($aps2) -join ";")

        FileSystem      = $fs
        Label           = $label
        VolumeSizeBytes = $size
        FreeBytes       = $free
        VolHealth       = $health
        VolOpStatus     = $op
      }
      [void]$rows.Add($row)
    }
  }

  # Stable display (no implicit formatting drift)
  $rows | Sort-Object DiskNumber,PartitionNumber | Format-Table DiskNumber,PartitionNumber,DriveLetter,AccessPaths,FileSystem,Label,VolumeSizeBytes,FreeBytes,BusType,PartitionStyle -AutoSize

  $obj = [ordered]@{
    schema="storage.receipt.v1"
    action="inspect"
    time_utc=[DateTime]::UtcNow.ToString("o")
    host=$env:COMPUTERNAME
    disk_count=@($disks).Count
    row_count=@($rows).Count
  }
  [void](EmitReceipt $RepoRoot $obj)
  return
}

'@

$patched = $src.Substring(0, $m.Index) + $insert + $src.Substring($m.Index)

WriteUtf8NoBomLf $Target $patched
ParseGateFile $Target
Write-Output ("PATCH_OK LD_STORAGE_INSPECT_V1 target=" + $Target)