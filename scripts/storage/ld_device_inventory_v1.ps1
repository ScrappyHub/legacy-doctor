param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function NormalizeDriveLetter([object]$Value){
  if($null -eq $Value){ return "" }

  $s = [string]$Value
  $s = $s.Replace([string][char]0,"").Trim()

  if([string]::IsNullOrWhiteSpace($s)){ return "" }

  return $s
}
function EnsureDir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ return }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ EnsureDir $dir }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($Path,$t,[Text.UTF8Encoding]::new($false))
}

function Str([object]$Value){
  if($null -eq $Value){ return "" }
  return [string]$Value
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$disks = @()

foreach($disk in @(Get-Disk | Sort-Object Number)){
  $dn = [int]$disk.Number

  $parts = @()
  foreach($p in @(Get-Partition -DiskNumber $dn -ErrorAction SilentlyContinue | Sort-Object PartitionNumber)){
    $access = @()
    try {
      foreach($ap in @($p.AccessPaths)){
        if(-not [string]::IsNullOrWhiteSpace([string]$ap)){
          $access += [string]$ap
        }
      }
    } catch {
      $access = @()
    }

    $parts += ,([ordered]@{
      partition_number = [int]$p.PartitionNumber
      drive_letter = (NormalizeDriveLetter $p.DriveLetter)
      type = [string]$p.Type
      size_bytes = [UInt64]$p.Size
      access_paths = @($access)
    })
  }

  $vols = @()
  foreach($v in @(Get-Volume -ErrorAction SilentlyContinue | Sort-Object DriveLetter)){
    $vols += ,([ordered]@{
      drive_letter = [string]$v.DriveLetter
      path = [string]$v.Path
      file_system = [string]$v.FileSystem
      label = [string]$v.FileSystemLabel
      drive_type = [string]$v.DriveType
      health_status = [string]$v.HealthStatus
      operational_status = [string]$v.OperationalStatus
      size_bytes = $(if($null -ne $v.Size){ [UInt64]$v.Size } else { [UInt64]0 })
      size_remaining_bytes = $(if($null -ne $v.SizeRemaining){ [UInt64]$v.SizeRemaining } else { [UInt64]0 })
    })
  }

  $disks += ,([ordered]@{
    disk_number = $dn
    friendly_name = Str $disk.FriendlyName
    serial_number = Str $disk.SerialNumber
    bus_type = Str $disk.BusType
    partition_style = Str $disk.PartitionStyle
    operational_status = Str $disk.OperationalStatus
    health_status = Str $disk.HealthStatus
    is_boot = [bool]$disk.IsBoot
    is_system = [bool]$disk.IsSystem
    is_offline = [bool]$disk.IsOffline
    is_read_only = [bool]$disk.IsReadOnly
    size_bytes = [UInt64]$disk.Size
    partition_count = [int]$parts.Count
    partitions = @($parts)
  })
}

$receipt = [ordered]@{
  schema = "ld.device.inventory.receipt.v1"
  event_type = "ld.device.inventory.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  disk_count = [int]$disks.Count
  disks = @($disks)
  visible_volume_count = [int]$vols.Count
  visible_volumes = @($vols)
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
}

$outDir = Join-Path $RepoRoot "proofs\receipts\device_inventory"
EnsureDir $outDir
$stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")
$outPath = Join-Path $outDir ("inventory_" + $stamp + ".json")

$json = $receipt | ConvertTo-Json -Depth 80 -Compress
Write-Utf8NoBomLf -Path $outPath -Text $json

Write-Output ("DEVICE_INVENTORY_PATH: " + $outPath)
Write-Output ("DEVICE_INVENTORY_COUNT: " + [string]$disks.Count)
Write-Output $json
Write-Output "LD_DEVICE_INVENTORY_OK"
