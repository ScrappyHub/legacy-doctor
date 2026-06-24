param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [int]$MaxFilesPerSource = 200,
  [int]$MaxDirsPerSource = 75,
  [int]$MaxSamplesPerSource = 25
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

function ShouldExcludeName([string]$Name,[object[]]$Rules){
  foreach($r in @($Rules)){
    $rule = [string]$r
    if([string]::IsNullOrWhiteSpace($rule)){ continue }
    if($Name -ieq $rule){ return $true }
  }
  return $false
}

function RelativePath([string]$Root,[string]$Path){
  if([string]::IsNullOrWhiteSpace($Root) -or [string]::IsNullOrWhiteSpace($Path)){ return $Path }

  $r = $Root
  if(-not $r.EndsWith("\")){ $r += "\" }

  if($Path.StartsWith($r,[StringComparison]::OrdinalIgnoreCase)){
    return $Path.Substring($r.Length)
  }

  return $Path
}

function Enumerate-Source([object]$PlanRow,[int]$MaxFiles,[int]$MaxDirs,[int]$MaxSamples){
  $sourceRoot = SafeStr $PlanRow.source_drive
  $excludeRules = @($PlanRow.exclude_rules)

  $fileCount = 0
  $dirCount = 0
  $byteCount = [Int64]0
  $errorCount = 0
  $truncated = $false
  $samples = @()
  $errors = @()

  if([string]::IsNullOrWhiteSpace($sourceRoot)){
    return [ordered]@{
      source_drive = $sourceRoot
      ok = $false
      state = "SOURCE_MISSING"
      file_count = 0
      dir_count = 0
      bytes_seen = 0
      error_count = 0
      truncated = $false
      samples = @()
      errors = @("source drive is empty")
    }
  }

  if(-not (Test-Path -LiteralPath $sourceRoot -PathType Container)){
    return [ordered]@{
      source_drive = $sourceRoot
      ok = $false
      state = "SOURCE_NOT_FOUND"
      file_count = 0
      dir_count = 0
      bytes_seen = 0
      error_count = 0
      truncated = $false
      samples = @()
      errors = @("source drive not found")
    }
  }

  $stack = New-Object System.Collections.Generic.Stack[string]
  $stack.Push($sourceRoot)

  while($stack.Count -gt 0){
    if($dirCount -ge $MaxDirs -or $fileCount -ge $MaxFiles){
      $truncated = $true
      break
    }

    $dir = $stack.Pop()
    $dirName = Split-Path -Leaf $dir

    if(ShouldExcludeName -Name $dirName -Rules $excludeRules){
      continue
    }

    $dirCount++

    try {
      foreach($file in [IO.Directory]::EnumerateFiles($dir)){
        if($fileCount -ge $MaxFiles){
          $truncated = $true
          break
        }

        $name = [IO.Path]::GetFileName($file)
        if(ShouldExcludeName -Name $name -Rules $excludeRules){
          continue
        }

        try {
          $fi = New-Object IO.FileInfo($file)
          $len = [Int64]0
          if($fi.Exists){ $len = [Int64]$fi.Length }

          $fileCount++
          $byteCount += $len

          if(@($samples).Count -lt $MaxSamples){
            $samples += ,([ordered]@{
              relative_path = RelativePath -Root $sourceRoot -Path $fi.FullName
              size_bytes = $len
              last_write_utc = $fi.LastWriteTimeUtc.ToString("o")
            })
          }
        } catch {
          $errorCount++
          if(@($errors).Count -lt 20){ $errors += $_.Exception.Message }
        }
      }
    } catch {
      $errorCount++
      if(@($errors).Count -lt 20){ $errors += $_.Exception.Message }
    }

    try {
      foreach($child in [IO.Directory]::EnumerateDirectories($dir)){
        if($dirCount -ge $MaxDirs){
          $truncated = $true
          break
        }

        $childName = Split-Path -Leaf $child
        if(ShouldExcludeName -Name $childName -Rules $excludeRules){
          continue
        }

        $stack.Push($child)
      }
    } catch {
      $errorCount++
      if(@($errors).Count -lt 20){ $errors += $_.Exception.Message }
    }
  }

  $state = "ENUMERATED_DRY_RUN_ONLY"
  if($truncated){ $state = "ENUMERATED_DRY_RUN_TRUNCATED" }

  return [ordered]@{
    source_drive = $sourceRoot
    ok = $true
    state = $state
    source_volume_label = SafeStr $PlanRow.source_volume_label
    source_disk_number = [int]$PlanRow.source_disk_number
    source_partition_number = [int]$PlanRow.source_partition_number
    system_disk_warning = SafeBool $PlanRow.system_disk_warning
    required_bytes_estimate = SafeI64 $PlanRow.required_bytes_estimate
    file_count = [int]$fileCount
    dir_count = [int]$dirCount
    bytes_seen = [Int64]$byteCount
    error_count = [int]$errorCount
    truncated = [bool]$truncated
    max_files = [int]$MaxFiles
    max_dirs = [int]$MaxDirs
    max_samples = [int]$MaxSamples
    samples = @($samples)
    errors = @($errors)
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$PlanScript = Join-Path $RepoRoot "scripts\storage\ld_file_backup_plan_v1.ps1"
if(-not (Test-Path -LiteralPath $PlanScript -PathType Leaf)){
  Die "FILE_BACKUP_PLAN_SCRIPT_MISSING" $PlanScript
}

$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PlanScript -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){
  Die "FILE_BACKUP_PLAN_EXIT_NONZERO" ([string]$LASTEXITCODE)
}

$plan = First-JsonObjectFromOutput -Output $out -Schema "ld.device.file_backup_plan.receipt.v1"

$rows = @()
foreach($p in @($plan.plan_rows)){
  $rows += ,(Enumerate-Source -PlanRow $p -MaxFiles $MaxFilesPerSource -MaxDirs $MaxDirsPerSource -MaxSamples $MaxSamplesPerSource)
}

$totalFiles = 0
$totalDirs = 0
$totalBytes = [Int64]0
$totalErrors = 0
$truncatedCount = 0

foreach($r in @($rows)){
  $totalFiles += [int]$r.file_count
  $totalDirs += [int]$r.dir_count
  $totalBytes += [Int64]$r.bytes_seen
  $totalErrors += [int]$r.error_count
  if([bool]$r.truncated){ $truncatedCount++ }
}

$receipt = [ordered]@{
  schema = "ld.device.backup_dry_run_enumerator.receipt.v1"
  event_type = "ld.device.backup_dry_run_enumerator.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  mode = "backup_dry_run_enumerator"
  destructive = $false
  write_test = $false
  performs_copy = $false
  reads_file_metadata = $true
  plan_row_count = [int]$plan.planned_count
  enumerated_source_count = [int]$rows.Count
  total_file_count = [int]$totalFiles
  total_dir_count = [int]$totalDirs
  total_bytes_seen = [Int64]$totalBytes
  total_error_count = [int]$totalErrors
  truncated_source_count = [int]$truncatedCount
  rows = @($rows)
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
}

$outDir = Join-Path $RepoRoot "proofs\receipts\device_backup_dry_run_enumerator"
EnsureDir $outDir
$outPath = Join-Path $outDir ("backup_dry_run_enumerator_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff") + ".json")

$json = $receipt | ConvertTo-Json -Depth 100 -Compress
Write-Utf8NoBomLf -Path $outPath -Text $json

Write-Output ("DEVICE_BACKUP_DRY_RUN_ENUMERATOR_PATH: " + $outPath)
Write-Output ("DEVICE_BACKUP_DRY_RUN_ENUMERATOR_SOURCES: " + [string]$rows.Count)
Write-Output ("DEVICE_BACKUP_DRY_RUN_ENUMERATOR_FILES: " + [string]$totalFiles)
Write-Output $json
Write-Output "LD_DEVICE_BACKUP_DRY_RUN_ENUMERATOR_OK"
