param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SourceRoot,
  [Parameter(Mandatory=$true)][string]$DestinationRoot,
  [int]$MaxFiles = 1000,
  [Int64]$MaxBytes = 1073741824,
  [switch]$Execute
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){ throw ($Code + ":" + $Detail) }

$ReceiptsLib = Join-Path $PSScriptRoot "..\storage\_lib_ld_receipts_v1.ps1"
if(-not (Test-Path -LiteralPath $ReceiptsLib -PathType Leaf)){ Die "RECEIPT_LIBRARY_MISSING" $ReceiptsLib }
. $ReceiptsLib

function EnsureDir([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  EnsureDir (Split-Path -Parent $Path)
  $normalized = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $normalized.EndsWith("`n")){ $normalized += "`n" }
  [IO.File]::WriteAllText($Path,$normalized,[Text.UTF8Encoding]::new($false))
}

function Add-Unique([object[]]$Items,[string]$Value){
  $result = @($Items)
  if(-not ($result -contains $Value)){ $result += $Value }
  return @($result)
}

function CanonicalPath([string]$Path){
  return [IO.Path]::GetFullPath($Path).TrimEnd("\")
}

function SameOrNested([string]$A,[string]$B){
  $aFull = CanonicalPath $A
  $bFull = CanonicalPath $B
  if($aFull.Equals($bFull,[StringComparison]::OrdinalIgnoreCase)){ return $true }
  return $aFull.StartsWith(($bFull + "\"),[StringComparison]::OrdinalIgnoreCase)
}

function PathUnderRoot([string]$Root,[string]$Path){
  $rootFull = CanonicalPath $Root
  $pathFull = CanonicalPath $Path
  return $pathFull.StartsWith(($rootFull + "\"),[StringComparison]::OrdinalIgnoreCase)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
if(-not (Test-Path -LiteralPath $SourceRoot -PathType Container)){ Die "SOURCE_ROOT_MISSING" $SourceRoot }
$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path

$destinationExists = Test-Path -LiteralPath $DestinationRoot -PathType Container
$destinationResolved = $(if($destinationExists){ (Resolve-Path -LiteralPath $DestinationRoot).Path } else { [IO.Path]::GetFullPath($DestinationRoot) })
$DestinationRoot = $destinationResolved
if($MaxFiles -lt 1){ Die "MAX_FILES_INVALID" ([string]$MaxFiles) }
if($MaxBytes -lt 1){ Die "MAX_BYTES_INVALID" ([string]$MaxBytes) }

$decisions = @()
$blockers = @()
if(-not $Execute.IsPresent){ $decisions = Add-Unique $decisions "DRY_RUN_ONLY" }
if(-not $destinationExists){ $blockers = Add-Unique $blockers "DESTINATION_MISSING" }
if((CanonicalPath $DestinationRoot).Equals((CanonicalPath $RepoRoot),[StringComparison]::OrdinalIgnoreCase)){
  $blockers = Add-Unique $blockers "REPO_ROOT_DESTINATION_FORBIDDEN"
}
if((SameOrNested -A $DestinationRoot -B $SourceRoot) -or (SameOrNested -A $SourceRoot -B $DestinationRoot)){
  $blockers = Add-Unique $blockers "SOURCE_DESTINATION_OVERLAP"
}

$catalogScript = Join-Path $RepoRoot "scripts\media\ld_media_catalog_v1.ps1"
$catalog = LDREC-RunReceiptScript -ScriptPath $catalogScript -RepoRoot $RepoRoot -ExpectedSchema "ld.media.catalog.receipt.v1" -ExtraArgs @("-SourceRoot",$SourceRoot,"-MaxFiles",[string]$MaxFiles,"-MaxBytes",[string]$MaxBytes)
if([bool]$catalog.truncated){ $blockers = Add-Unique $blockers "CATALOG_TRUNCATED" }
if([int]$catalog.file_count -le 0){ $blockers = Add-Unique $blockers "EMPTY_CATALOG" }

$rows = @()
foreach($catalogRow in @($catalog.files)){
  $relative = [string]$catalogRow.relative_path
  $sourcePath = Join-Path $SourceRoot $relative.Replace("/","\")
  $destinationPath = Join-Path $DestinationRoot $relative.Replace("/","\")
  $tempPath = $destinationPath + ".legacy-doctor.partial"
  $rowBlockers = @()
  if(-not (PathUnderRoot -Root $DestinationRoot -Path $destinationPath)){ $rowBlockers = Add-Unique $rowBlockers "DESTINATION_ESCAPE" }
  if(Test-Path -LiteralPath $destinationPath){ $rowBlockers = Add-Unique $rowBlockers "DESTINATION_COLLISION" }
  if(Test-Path -LiteralPath $tempPath){ $rowBlockers = Add-Unique $rowBlockers "STALE_PARTIAL_COLLISION" }
  foreach($rowBlocker in $rowBlockers){ $blockers = Add-Unique $blockers $rowBlocker }

  $rows += ,([ordered]@{
    relative_path = $relative
    source_path = $sourcePath
    destination_path = $destinationPath
    size_bytes = [Int64]$catalogRow.size_bytes
    expected_sha256 = [string]$catalogRow.sha256
    destination_sha256 = ""
    category = [string]$catalogRow.category
    status = $(if(@($rowBlockers).Count -eq 0){ "PLANNED" } else { "BLOCKED" })
    blockers = @($rowBlockers)
  })
}

$writeProbeOk = $false
if($Execute.IsPresent -and $destinationExists -and @($blockers).Count -eq 0){
  $probeScript = Join-Path $RepoRoot "scripts\storage\ld_destination_write_probe_v1.ps1"
  $probe = LDREC-RunReceiptScript -ScriptPath $probeScript -RepoRoot $RepoRoot -ExpectedSchema "ld.device.destination_write_probe.receipt.v1" -ExtraArgs @("-DestinationPath",$DestinationRoot)
  $writeProbeOk = [bool]$probe.write_probe_ok
  if(-not $writeProbeOk){ $blockers = Add-Unique $blockers "DESTINATION_WRITE_PROBE_FAILED" }
}

$preflightReady = (@($blockers).Count -eq 0)
$executionAllowed = ($Execute.IsPresent -and $preflightReady)
$copiedCount = 0
$copiedBytes = [Int64]0
$verifiedCount = 0
$writeAttempted = $false
$executionFailed = $false
$createdFiles = @()

if($executionAllowed){
  foreach($row in $rows){
    $tempPath = [string]$row.destination_path + ".legacy-doctor.partial"
    try {
      $sourceHashBefore = (Get-FileHash -LiteralPath $row.source_path -Algorithm SHA256).Hash.ToLowerInvariant()
      if($sourceHashBefore -cne [string]$row.expected_sha256){ throw "SOURCE_CHANGED_BEFORE_COPY" }

      EnsureDir (Split-Path -Parent ([string]$row.destination_path))
      $writeAttempted = $true
      [IO.File]::Copy([string]$row.source_path,$tempPath,$false)
      $tempHash = (Get-FileHash -LiteralPath $tempPath -Algorithm SHA256).Hash.ToLowerInvariant()
      if($tempHash -cne [string]$row.expected_sha256){ throw "TEMP_HASH_MISMATCH" }

      [IO.File]::Move($tempPath,[string]$row.destination_path)
      $createdFiles += [string]$row.destination_path
      $destinationHash = (Get-FileHash -LiteralPath $row.destination_path -Algorithm SHA256).Hash.ToLowerInvariant()
      $sourceHashAfter = (Get-FileHash -LiteralPath $row.source_path -Algorithm SHA256).Hash.ToLowerInvariant()
      if($destinationHash -cne [string]$row.expected_sha256){ throw "DESTINATION_HASH_MISMATCH" }
      if($sourceHashAfter -cne [string]$row.expected_sha256){ throw "SOURCE_CHANGED_DURING_COPY" }

      $row.destination_sha256 = $destinationHash
      $row.status = "COPIED_VERIFIED"
      $copiedCount++
      $verifiedCount++
      $copiedBytes += [Int64]$row.size_bytes
    } catch {
      $executionFailed = $true
      $row.status = "COPY_FAILED"
      $row.blockers = @([string]$_.Exception.Message)
      if(Test-Path -LiteralPath $tempPath -PathType Leaf){ Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
      break
    }
  }
}

$rollbackPerformed = $false
$rollbackOk = $true
if($executionFailed){
  $blockers = Add-Unique $blockers "EXECUTION_FAILED"
  $rollbackPerformed = $true
  foreach($createdFile in @($createdFiles)){
    try {
      if(Test-Path -LiteralPath $createdFile -PathType Leaf){ Remove-Item -LiteralPath $createdFile -Force }
    } catch {
      $rollbackOk = $false
    }
  }
}

$status = "dry_run_blocked"
$ok = $false
$availability = "blocked"
if(-not $Execute.IsPresent -and $preflightReady){ $status = "dry_run_ready"; $ok = $true; $availability = "available" }
elseif($Execute.IsPresent -and $executionAllowed -and -not $executionFailed -and $verifiedCount -eq (@($rows).Count)){ $status = "executed_verified"; $ok = $true; $availability = "available" }
elseif($executionFailed -and $rollbackOk){ $status = "execution_failed_rolled_back"; $availability = "failed" }
elseif($executionFailed){ $status = "execution_failed_rollback_incomplete"; $availability = "failed" }

$receipt = [ordered]@{
  schema = "ld.media.mounted_backup.receipt.v1"
  event_type = "ld.media.mounted_backup.receipt.v1"
  ok = [bool]$ok
  availability = $availability
  repo_root = $RepoRoot
  source_root = $SourceRoot
  destination_root = $DestinationRoot
  mode = "mounted_media_backup"
  destructive = $false
  writes_source = $false
  execute_requested = [bool]$Execute.IsPresent
  preflight_ready = [bool]$preflightReady
  execution_allowed = [bool]$executionAllowed
  performs_copy = [bool]($copiedCount -gt 0)
  writes_destination = [bool]$writeAttempted
  hashes_file_contents = $true
  catalog_schema = "ld.media.catalog.receipt.v1"
  catalog_sha256 = [string]$catalog.catalog_sha256
  max_files = $MaxFiles
  max_bytes = $MaxBytes
  catalog_truncated = [bool]$catalog.truncated
  planned_file_count = [int](@($rows).Count)
  planned_bytes = [Int64]$catalog.total_bytes
  copied_file_count = [int]$copiedCount
  copied_bytes = [Int64]$copiedBytes
  verified_file_count = [int]$verifiedCount
  write_probe_ok = [bool]$writeProbeOk
  rollback_performed = [bool]$rollbackPerformed
  rollback_ok = [bool]$rollbackOk
  execution_status = $status
  decisions = @($decisions)
  blockers = @($blockers)
  rows = @($rows)
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$outDir = Join-Path $RepoRoot "proofs\receipts\mounted_media_backup"
$outPath = Join-Path $outDir ("mounted_media_backup_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff") + ".json")
$json = $receipt | ConvertTo-Json -Depth 100 -Compress
Write-Utf8NoBomLf -Path $outPath -Text $json

Write-Output ("MOUNTED_MEDIA_BACKUP_PATH: " + $outPath)
Write-Output ("MOUNTED_MEDIA_BACKUP_STATUS: " + $status)
Write-Output $json
if($ok){ Write-Output "LD_MOUNTED_MEDIA_BACKUP_OK" } else { Write-Output "LD_MOUNTED_MEDIA_BACKUP_BLOCKED" }
