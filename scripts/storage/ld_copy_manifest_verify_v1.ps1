param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$DestinationRoot = "",
  [int]$MaxFilesPerSource = 20,
  [int]$MaxDirsPerSource = 10,
  [int]$MaxSamplesPerSource = 5
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

function First-JsonObjectFromOutput([object[]]$Output,[string]$Schema){
  foreach($line in @($Output)){
    $s = [string]$line
    if($s.StartsWith("{") -and $s.Contains(('"schema":"' + $Schema + '"'))){
      return ($s | ConvertFrom-Json)
    }
  }

  Die "JSON_SCHEMA_OUTPUT_MISSING" $Schema
}

function SafeStr([object]$Value){
  if($null -eq $Value){ return "" }
  return [string]$Value
}

function SafeBool([object]$Value){
  if($null -eq $Value){ return $false }
  return [bool]$Value
}

function SafeI64([object]$Value){
  if($null -eq $Value){ return [Int64]0 }
  return [Int64]$Value
}

function Add-Unique([object[]]$Items,[string]$Value){
  $out = @($Items)
  if(-not ($out -contains $Value)){ $out += $Value }
  return @($out)
}

function PathUnderRoot([string]$Root,[string]$Path){
  if([string]::IsNullOrWhiteSpace($Root) -or [string]::IsNullOrWhiteSpace($Path)){ return $false }

  try {
    $rootFull = [IO.Path]::GetFullPath($Root)
    $pathFull = [IO.Path]::GetFullPath($Path)

    if(-not $rootFull.EndsWith("\")){ $rootFull += "\" }

    return $pathFull.StartsWith($rootFull,[StringComparison]::OrdinalIgnoreCase)
  } catch {
    return $false
  }
}

function RelLooksSafe([string]$Rel){
  if([string]::IsNullOrWhiteSpace($Rel)){ return $false }

  $r = $Rel.Replace("/","\")
  if($r.StartsWith("\")){ return $false }
  if($r -match "^[A-Za-z]:"){ return $false }

  foreach($part in @($r.Split("\"))){
    if($part -eq ".."){ return $false }
  }

  return $true
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$ManifestScript = Join-Path $RepoRoot "scripts\storage\ld_copy_manifest_dry_run_v1.ps1"
if(-not (Test-Path -LiteralPath $ManifestScript -PathType Leaf)){
  Die "COPY_MANIFEST_DRY_RUN_SCRIPT_MISSING" $ManifestScript
}

$args = @(
  "-NoProfile",
  "-NonInteractive",
  "-ExecutionPolicy","Bypass",
  "-File",$ManifestScript,
  "-RepoRoot",$RepoRoot,
  "-MaxFilesPerSource",[string]$MaxFilesPerSource,
  "-MaxDirsPerSource",[string]$MaxDirsPerSource,
  "-MaxSamplesPerSource",[string]$MaxSamplesPerSource
)

if(-not [string]::IsNullOrWhiteSpace($DestinationRoot)){
  $args += @("-DestinationRoot",$DestinationRoot)
}

$out = & powershell.exe @args
if($LASTEXITCODE -ne 0){
  Die "COPY_MANIFEST_DRY_RUN_EXIT_NONZERO" ([string]$LASTEXITCODE)
}

$manifest = First-JsonObjectFromOutput -Output $out -Schema "ld.device.copy_manifest_dry_run.receipt.v1"

$verifyRows = @()
$validCount = 0
$invalidCount = 0
$warnCount = 0

foreach($m in @($manifest.manifest_rows)){
  $errors = @()
  $warnings = @()

  $sourcePath = SafeStr $m.source_path
  $destRoot = SafeStr $m.destination_root
  $destPath = SafeStr $m.destination_path
  $destRel = SafeStr $m.destination_relative_path
  $expectedSize = SafeI64 $m.size_bytes

  if((SafeStr $m.copy_action) -ne "WOULD_COPY"){
    $errors = Add-Unique $errors "COPY_ACTION_NOT_WOULD_COPY"
  }

  if([string]::IsNullOrWhiteSpace($sourcePath)){
    $errors = Add-Unique $errors "SOURCE_PATH_MISSING"
  } elseif(-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    $errors = Add-Unique $errors "SOURCE_PATH_NOT_FOUND"
  } else {
    try {
      $fi = New-Object IO.FileInfo($sourcePath)
      if([Int64]$fi.Length -ne $expectedSize){
        $errors = Add-Unique $errors "SOURCE_SIZE_MISMATCH"
      }
    } catch {
      $errors = Add-Unique $errors "SOURCE_METADATA_READ_FAILED"
    }
  }

  if([string]::IsNullOrWhiteSpace($destRoot)){
    $errors = Add-Unique $errors "DESTINATION_ROOT_MISSING"
  }

  if([string]::IsNullOrWhiteSpace($destPath)){
    $errors = Add-Unique $errors "DESTINATION_PATH_MISSING"
  }

  if(-not (RelLooksSafe $destRel)){
    $errors = Add-Unique $errors "DESTINATION_RELATIVE_PATH_UNSAFE"
  }

  if(-not (PathUnderRoot -Root $destRoot -Path $destPath)){
    $errors = Add-Unique $errors "DESTINATION_PATH_ESCAPES_ROOT"
  }

  if(SafeBool $m.system_disk_warning){
    $warnings = Add-Unique $warnings "SYSTEM_DISK_WARNING_CARRIED"
  }

  if(SafeBool $m.content_hash_claimed){
    $errors = Add-Unique $errors "CONTENT_HASH_FORBIDDEN_IN_DRY_RUN_VERIFY"
  }

  $ok = (@($errors).Count -eq 0)
  if($ok){ $validCount++ } else { $invalidCount++ }
  if(@($warnings).Count -gt 0){ $warnCount++ }

  $verifyRows += ,([ordered]@{
    source_path = $sourcePath
    destination_path = $destPath
    destination_root = $destRoot
    destination_relative_path = $destRel
    expected_size_bytes = $expectedSize
    verify_ok = [bool]$ok
    errors = @($errors)
    warnings = @($warnings)
    copy_action = SafeStr $m.copy_action
    system_disk_warning = SafeBool $m.system_disk_warning
  })
}

$skippedRows = @()
foreach($s in @($manifest.skipped_rows)){
  $skippedRows += ,([ordered]@{
    copy_action = SafeStr $s.copy_action
    source_drive = SafeStr $s.source_drive
    reason = SafeStr $s.reason
    preserved = $true
  })
}

$overallOk = ($invalidCount -eq 0)

$receipt = [ordered]@{
  schema = "ld.device.copy_manifest_verify.receipt.v1"
  event_type = "ld.device.copy_manifest_verify.receipt.v1"
  ok = [bool]$overallOk
  repo_root = $RepoRoot
  mode = "copy_manifest_verify"
  destructive = $false
  write_test = $false
  performs_copy = $false
  writes_destination = $false
  hashes_file_contents = $false
  consumes_manifest_schema = "ld.device.copy_manifest_dry_run.receipt.v1"
  manifest_row_count = [int]$manifest.manifest_row_count
  verified_row_count = [int]$verifyRows.Count
  valid_row_count = [int]$validCount
  invalid_row_count = [int]$invalidCount
  warning_row_count = [int]$warnCount
  skipped_row_count = [int]$skippedRows.Count
  source_error_count = [int]$manifest.source_error_count
  rows = @($verifyRows)
  skipped_rows = @($skippedRows)
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
}

$outDir = Join-Path $RepoRoot "proofs\receipts\device_copy_manifest_verify"
EnsureDir $outDir
$outPath = Join-Path $outDir ("copy_manifest_verify_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff") + ".json")

$json = $receipt | ConvertTo-Json -Depth 100 -Compress
Write-Utf8NoBomLf -Path $outPath -Text $json

Write-Output ("DEVICE_COPY_MANIFEST_VERIFY_PATH: " + $outPath)
Write-Output ("DEVICE_COPY_MANIFEST_VERIFY_ROWS: " + [string]$verifyRows.Count)
Write-Output ("DEVICE_COPY_MANIFEST_VERIFY_INVALID: " + [string]$invalidCount)
Write-Output $json
Write-Output "LD_DEVICE_COPY_MANIFEST_VERIFY_OK"
