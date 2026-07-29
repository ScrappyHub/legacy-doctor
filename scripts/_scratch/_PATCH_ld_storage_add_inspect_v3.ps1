# =====================================================================
# PATCH: LD-STORAGE-01 add "inspect" command handler (StrictMode-safe)
# Target: scripts\storage\ld_storage_v1.ps1
# Sentinel: LD_STORAGE_INSPECT_V1
# Also ensures Cmd ValidateSet includes "inspect"
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

# 1) Ensure ValidateSet includes inspect (idempotent)
#    Replace ValidateSet("list","format") with ValidateSet("list","format","inspect") only if inspect not present.
if($src -match '\[ValidateSet\("list","format"\)\]\[string\]\$Cmd'){
  $src = [regex]::Replace(
    $src,
    '\[ValidateSet\("list","format"\)\]\[string\]\$Cmd',
    '[ValidateSet("list","format","inspect")][string]$Cmd',
    1
  )
}

# If already has inspect sentinel, just write ValidateSet update (if any) and exit clean.
if($src -match 'LD_STORAGE_INSPECT_V1'){
  WriteUtf8NoBomLf $Target $src
  ParseGateFile $Target
  Write-Output ("OK: already has LD_STORAGE_INSPECT_V1 target=" + $Target)
  exit 0
}

# 2) Insert inspect branch before the UNKNOWN_CMD format gate
$needle = 'if\(\$Cmd\s*-ne\s*"format"\s*\)\s*\{\s*Die\s*\(\s*\("UNKNOWN_CMD:\s*"\s*\+\s*\$Cmd\)\s*\)\s*\}\s*'
$m = [regex]::Match($src, $needle)
if(-not $m.Success){
  throw 'PATCH_FAIL: could not locate UNKNOWN_CMD format gate. Expected: if($Cmd -ne "format"){ Die ("UNKNOWN_CMD: " + $Cmd) }'
}

$insert = @'
# === LD_STORAGE_INSPECT_V1 ===
if($Cmd -eq "inspect"){
  # Enumerate disks + partitions + volume info (even when no drive letter assigned).
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
      $vsz = $null
      $free = $null
      $health = ""
      $op = ""
      try {
        if(-not [string]::IsNullOrWhiteSpace($dl)){
          $v = Get-Volume -DriveLetter $dl -ErrorAction Stop
          $fs = [string]$v.FileSystem
          $label = [string]$v.FileSystemLabel
          $vsz = $v.Size
          $free = $v.SizeRemaining
          $health = [string]$v.HealthStatus
          $op = [string]$v.OperationalStatus
        }
      } catch { }

      $row = [pscustomobject]@{
        DiskNumber      = $d.Number
        DeviceId        = (MakeDeviceId $d)
        FriendlyName    = $d.FriendlyName
        BusType         = ([string]$d.BusType)
        DiskSizeBytes   = $d.Size
        PartitionStyle  = ([string]$d.PartitionStyle)

        PartitionNumber = $p.PartitionNumber
        DriveLetter     = $dl
        AccessPaths     = (@($aps2) -join ";")

        FileSystem      = $fs
        Label           = $label
        VolumeSizeBytes = $vsz
        FreeBytes       = $free
        VolHealth       = $health
        VolOpStatus     = $op
      }
      [void]$rows.Add($row)
    }
  }

  $rows | Sort-Object DiskNumber,PartitionNumber |
    Format-Table DiskNumber,PartitionNumber,DriveLetter,AccessPaths,FileSystem,Label,VolumeSizeBytes,FreeBytes,BusType,PartitionStyle,FriendlyName -AutoSize

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