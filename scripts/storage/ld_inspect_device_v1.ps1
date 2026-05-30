param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][int]$DiskNumber
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function EnsureDir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ return }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Utf8NoBom(){
  return (New-Object System.Text.UTF8Encoding($false))
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ EnsureDir $dir }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($Path,$t,(Utf8NoBom))
}

function Append-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ EnsureDir $dir }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::AppendAllText($Path,$t,(Utf8NoBom))
}

function HexSha256Bytes([byte[]]$Bytes){
  if($null -eq $Bytes){ $Bytes = [byte[]]@() }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($Bytes)
  } finally {
    $sha.Dispose()
  }
  $sb = New-Object System.Text.StringBuilder
  foreach($b in $hash){
    [void]$sb.Append($b.ToString("x2"))
  }
  return $sb.ToString()
}

function HexSha256TextLf([string]$Text){
  if($null -eq $Text){ $Text = "" }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  return (HexSha256Bytes ([Text.Encoding]::UTF8.GetBytes($t)))
}

function Append-Receipt([string]$LedgerPath,[object]$Receipt){
  $json = ($Receipt | ConvertTo-Json -Depth 40 -Compress)
  $hash = HexSha256TextLf $json

  $o = [ordered]@{}
  foreach($p in $Receipt.PSObject.Properties.Name){
    $o[$p] = $Receipt.$p
  }
  $o["receipt_hash"] = $hash

  Append-Utf8NoBomLf $LedgerPath (($o | ConvertTo-Json -Depth 40 -Compress))
  return $hash
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$ProbeLib = Join-Path $RepoRoot "scripts\storage\_lib_ld_device_probe_v1.ps1"
$HealthLib = Join-Path $RepoRoot "scripts\storage\_lib_ld_health_v1.ps1"
$InspectSchema = Join-Path $RepoRoot "schemas\ld.device.inspect.receipt.v1.json"
$HealthSchema = Join-Path $RepoRoot "schemas\ld.device.health.receipt.v1.json"

foreach($p in @($ProbeLib,$HealthLib,$InspectSchema,$HealthSchema)){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
    Die "MISSING_DEP" $p
  }
}

. $ProbeLib
. $HealthLib

$probe = LDPROBE-GetDiskProbe -DiskNumber $DiskNumber

$parts = @()
foreach($x in @($probe.partitions)){ $parts += ,([pscustomobject]$x) }

$vols = @()
foreach($x in @($probe.volumes)){ $vols += ,([pscustomobject]$x) }

$inspectReceipt = [pscustomobject]@{
  schema = "ld.device.inspect.receipt.v1"
  event_type = "ld.device.inspect.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  device_id = [string]$probe.device_id
  disk_number = [int]$probe.disk_number
  friendly_name = [string]$probe.friendly_name
  serial_number = [string]$probe.serial_number
  bus_type = [string]$probe.bus_type
  partition_style = [string]$probe.partition_style
  is_boot = [bool]$probe.is_boot
  is_system = [bool]$probe.is_system
  operational_status = [string]$probe.operational_status
  health_status = [string]$probe.health_status
  size_bytes = [UInt64]$probe.size_bytes
  partitions = @($parts)
  volumes = @($vols)
  preservation_recommendation = (LDHEALTH-GetRecommendation -Probe $probe)
}

$healthReceipt = [pscustomobject]@{
  schema = "ld.device.health.receipt.v1"
  event_type = "ld.device.health.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  device_id = [string]$probe.device_id
  disk_number = [int]$probe.disk_number
  health_summary = (LDHEALTH-GetHealthSummary -Probe $probe)
  signals = @((LDHEALTH-GetHealthSignals -Probe $probe))
  preservation_recommendation = (LDHEALTH-GetRecommendation -Probe $probe)
}

$OutDir = Join-Path $RepoRoot "proofs\receipts\device_inspect"
EnsureDir $OutDir

$stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")
$base = ("disk_" + $DiskNumber + "_" + $stamp)

$InspectPath = Join-Path $OutDir ($base + ".inspect.json")
$HealthPath  = Join-Path $OutDir ($base + ".health.json")
$LedgerPath  = Join-Path $RepoRoot "proofs\receipts\device_inspect.ndjson"

$inspectJson = ($inspectReceipt | ConvertTo-Json -Depth 40 -Compress)
$healthJson = ($healthReceipt | ConvertTo-Json -Depth 40 -Compress)

Write-Utf8NoBomLf $InspectPath $inspectJson
Write-Utf8NoBomLf $HealthPath $healthJson

$inspectHash = Append-Receipt -LedgerPath $LedgerPath -Receipt $inspectReceipt
$healthHash = Append-Receipt -LedgerPath $LedgerPath -Receipt $healthReceipt

Write-Host ("INSPECT_PATH: " + $InspectPath) -ForegroundColor Green
Write-Host ("HEALTH_PATH: " + $HealthPath) -ForegroundColor Green
Write-Host ("INSPECT_RECEIPT_HASH: " + $inspectHash) -ForegroundColor Green
Write-Host ("HEALTH_RECEIPT_HASH: " + $healthHash) -ForegroundColor Green
Write-Output $inspectJson
Write-Output $healthJson
Write-Output "LD_INSPECT_DEVICE_OK"
