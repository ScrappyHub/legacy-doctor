param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$DestinationPath = ""
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

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ EnsureDir $dir }

  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }

  [IO.File]::WriteAllText($Path,$t,[Text.UTF8Encoding]::new($false))
}

function Sha256HexBytes([byte[]]$Bytes){
  $sha = [Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($Bytes)
    return (($hash | ForEach-Object { $_.ToString("x2") }) -join "")
  } finally {
    $sha.Dispose()
  }
}

function SafeStr([object]$Value){
  if($null -eq $Value){ return "" }
  return [string]$Value
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

if([string]::IsNullOrWhiteSpace($DestinationPath)){
  $DestinationPath = $RepoRoot
}

$destinationInput = $DestinationPath
$destinationExists = Test-Path -LiteralPath $DestinationPath -PathType Container

$destinationResolved = ""
if($destinationExists){
  $destinationResolved = (Resolve-Path -LiteralPath $DestinationPath).Path
} else {
  try {
    $destinationResolved = [IO.Path]::GetFullPath($DestinationPath)
  } catch {
    $destinationResolved = $DestinationPath
  }
}

$tempPath = ""
$tempCreated = $false
$tempReadBack = $false
$tempHashOk = $false
$tempDeleted = $false
$writeOk = $false
$errorText = ""

$payloadText = "LEGACY_DOCTOR_DESTINATION_WRITE_PROBE_V1`n"
$payloadBytes = [Text.UTF8Encoding]::new($false).GetBytes($payloadText)
$expectedHash = Sha256HexBytes $payloadBytes
$actualHash = ""

if($destinationExists){
  $name = ".ld_destination_write_probe_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff") + "_" + ([Guid]::NewGuid().ToString("N")) + ".tmp"
  $tempPath = Join-Path $destinationResolved $name

  $fs = $null
  try {
    $fs = [IO.File]::Open($tempPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    $fs.Write($payloadBytes,0,$payloadBytes.Length)
    $fs.Flush($true)
    $fs.Dispose()
    $fs = $null

    $tempCreated = Test-Path -LiteralPath $tempPath -PathType Leaf

    $readBytes = [IO.File]::ReadAllBytes($tempPath)
    $tempReadBack = $true
    $actualHash = Sha256HexBytes $readBytes
    $tempHashOk = ($actualHash -eq $expectedHash)
    $writeOk = ($tempCreated -and $tempReadBack -and $tempHashOk)
  } catch {
    $errorText = $_.Exception.Message
  } finally {
    if($null -ne $fs){ $fs.Dispose() }

    try {
      if(Test-Path -LiteralPath $tempPath -PathType Leaf){
        Remove-Item -LiteralPath $tempPath -Force
      }
    } catch {
      if([string]::IsNullOrWhiteSpace($errorText)){
        $errorText = $_.Exception.Message
      }
    }

    $tempDeleted = (-not (Test-Path -LiteralPath $tempPath -PathType Leaf))
  }
} else {
  $errorText = "DESTINATION_MISSING"
}

$receipt = [ordered]@{
  schema = "ld.device.destination_write_probe.receipt.v1"
  event_type = "ld.device.destination_write_probe.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  mode = "destination_write_probe"
  destructive = $false
  write_test = $true
  performs_copy = $false
  destination_path_input = $destinationInput
  destination_path_resolved = $destinationResolved
  destination_exists = [bool]$destinationExists
  probe_file_path = $tempPath
  probe_payload_bytes = [int]$payloadBytes.Length
  expected_sha256 = $expectedHash
  actual_sha256 = $actualHash
  temp_created = [bool]$tempCreated
  temp_read_back = [bool]$tempReadBack
  temp_hash_ok = [bool]$tempHashOk
  temp_deleted = [bool]$tempDeleted
  write_probe_ok = [bool]$writeOk
  error = SafeStr $errorText
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
}

$outDir = Join-Path $RepoRoot "proofs\receipts\device_destination_write_probe"
EnsureDir $outDir
$outPath = Join-Path $outDir ("destination_write_probe_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff") + ".json")

$json = $receipt | ConvertTo-Json -Depth 80 -Compress
Write-Utf8NoBomLf -Path $outPath -Text $json

Write-Output ("DEVICE_DESTINATION_WRITE_PROBE_PATH: " + $outPath)
Write-Output ("DEVICE_DESTINATION_WRITE_PROBE_OK: " + [string]$writeOk)
Write-Output $json
Write-Output "LD_DEVICE_DESTINATION_WRITE_PROBE_OK"
