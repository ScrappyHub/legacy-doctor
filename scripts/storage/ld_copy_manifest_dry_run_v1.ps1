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

function NormalizeRel([string]$Path){
  $p = SafeStr $Path
  $p = $p.Replace("/","\")
  while($p.StartsWith("\")){ $p = $p.Substring(1) }
  return $p
}

function SourcePrefix([string]$SourceDrive,[string]$Label){
  $d = (SafeStr $SourceDrive).Replace(":","").Replace("\","").Trim()
  if([string]::IsNullOrWhiteSpace($d)){ $d = "UNKNOWN" }

  $l = (SafeStr $Label).Trim()
  $safeLabel = ""
  foreach($ch in $l.ToCharArray()){
    if([char]::IsLetterOrDigit($ch) -or $ch -eq "_" -or $ch -eq "-"){
      $safeLabel += [string]$ch
    } elseif($ch -eq " ") {
      $safeLabel += "_"
    }
  }

  if([string]::IsNullOrWhiteSpace($safeLabel)){
    return ("drive_" + $d)
  }

  return ("drive_" + $d + "_" + $safeLabel)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

if([string]::IsNullOrWhiteSpace($DestinationRoot)){
  $DestinationRoot = Join-Path $RepoRoot "_backup_destination_PLACEHOLDER"
}

$EnumScript = Join-Path $RepoRoot "scripts\storage\ld_backup_dry_run_enumerator_v1.ps1"
if(-not (Test-Path -LiteralPath $EnumScript -PathType Leaf)){
  Die "BACKUP_DRY_RUN_ENUMERATOR_SCRIPT_MISSING" $EnumScript
}

$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $EnumScript -RepoRoot $RepoRoot -MaxFilesPerSource $MaxFilesPerSource -MaxDirsPerSource $MaxDirsPerSource -MaxSamplesPerSource $MaxSamplesPerSource
if($LASTEXITCODE -ne 0){
  Die "BACKUP_DRY_RUN_ENUMERATOR_EXIT_NONZERO" ([string]$LASTEXITCODE)
}

$enum = First-JsonObjectFromOutput -Output $out -Schema "ld.device.backup_dry_run_enumerator.receipt.v1"

$manifestRows = @()
$skippedRows = @()

foreach($src in @($enum.rows)){
  $prefix = SourcePrefix -SourceDrive (SafeStr $src.source_drive) -Label (SafeStr $src.source_volume_label)

  foreach($sample in @($src.samples)){
    $rel = NormalizeRel (SafeStr $sample.relative_path)
    $destRel = Join-Path $prefix $rel

    $manifestRows += ,([ordered]@{
      copy_action = "WOULD_COPY"
      source_drive = SafeStr $src.source_drive
      source_relative_path = $rel
      source_path = ((SafeStr $src.source_drive) + $rel)
      destination_root = SafeStr $DestinationRoot
      destination_relative_path = $destRel
      destination_path = (Join-Path $DestinationRoot $destRel)
      size_bytes = SafeI64 $sample.size_bytes
      last_write_utc = SafeStr $sample.last_write_utc
      source_disk_number = [int]$src.source_disk_number
      source_partition_number = [int]$src.source_partition_number
      source_volume_label = SafeStr $src.source_volume_label
      system_disk_warning = SafeBool $src.system_disk_warning
      dry_run_only = $true
      content_hash_claimed = $false
    })
  }

  if([int]$src.error_count -gt 0){
    foreach($err in @($src.errors)){
      $skippedRows += ,([ordered]@{
        copy_action = "WOULD_SKIP_ERROR"
        source_drive = SafeStr $src.source_drive
        reason = SafeStr $err
        system_disk_warning = SafeBool $src.system_disk_warning
      })
    }
  }
}

$totalBytes = [Int64]0
foreach($m in @($manifestRows)){
  $totalBytes += [Int64]$m.size_bytes
}

$receipt = [ordered]@{
  schema = "ld.device.copy_manifest_dry_run.receipt.v1"
  event_type = "ld.device.copy_manifest_dry_run.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  mode = "copy_manifest_dry_run"
  destructive = $false
  write_test = $false
  performs_copy = $false
  writes_destination = $false
  hashes_file_contents = $false
  consumes_enumerator_schema = "ld.device.backup_dry_run_enumerator.receipt.v1"
  destination_root = SafeStr $DestinationRoot
  enumerated_source_count = [int]$enum.enumerated_source_count
  manifest_row_count = [int]$manifestRows.Count
  skipped_row_count = [int]$skippedRows.Count
  manifest_bytes = [Int64]$totalBytes
  truncated_source_count = [int]$enum.truncated_source_count
  source_error_count = [int]$enum.total_error_count
  manifest_rows = @($manifestRows)
  skipped_rows = @($skippedRows)
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
}

$outDir = Join-Path $RepoRoot "proofs\receipts\device_copy_manifest_dry_run"
EnsureDir $outDir
$outPath = Join-Path $outDir ("copy_manifest_dry_run_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff") + ".json")

$json = $receipt | ConvertTo-Json -Depth 100 -Compress
Write-Utf8NoBomLf -Path $outPath -Text $json

Write-Output ("DEVICE_COPY_MANIFEST_DRY_RUN_PATH: " + $outPath)
Write-Output ("DEVICE_COPY_MANIFEST_DRY_RUN_ROWS: " + [string]$manifestRows.Count)
Write-Output $json
Write-Output "LD_DEVICE_COPY_MANIFEST_DRY_RUN_OK"
