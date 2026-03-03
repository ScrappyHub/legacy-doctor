param(
  [Parameter(Mandatory=$true)][string]$RunDir
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "..\lib\doctor-common.ps1")

function Require-Path([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { throw "Missing required path: $p" }
}

Require-Path $RunDir
Require-Path (Join-Path $RunDir "manifest.v1.json")
Require-Path (Join-Path $RunDir "entitlements.v1.json")
Require-Path (Join-Path $RunDir "audit.v1.jsonl")

$artDir = Join-Path $RunDir "artifacts"
Ensure-Dir -Path $artDir | Out-Null

$runId = Split-Path -Leaf $RunDir
$ts = Get-Date -Format "yyyyMMdd_HHmmss"

# Define these EARLY so catch/finally can always reference them under StrictMode
$zipName = ("{0}__bundle_v1__{1}.zip" -f $runId, $ts)
$zipPath = Join-Path $artDir $zipName
$stage   = Join-Path $env:TEMP ("legacydoctor_pkg_stage_" + $runId + "_" + $ts)

try {
  if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $stage | Out-Null

  Audit-Append -RunDir $RunDir -Engine "package" -EventType "JOB_STARTED" -Action "package" -Subject $zipName -Details @{ stage=$stage }

  # Canonical files
  Copy-Item -LiteralPath (Join-Path $RunDir "manifest.v1.json")     -Destination (Join-Path $stage "manifest.v1.json")     -Force
  Copy-Item -LiteralPath (Join-Path $RunDir "entitlements.v1.json") -Destination (Join-Path $stage "entitlements.v1.json") -Force
  Copy-Item -LiteralPath (Join-Path $RunDir "audit.v1.jsonl")       -Destination (Join-Path $stage "audit.v1.jsonl")       -Force

  $hashFile = Join-Path $RunDir "sha256sums.txt"
  if (Test-Path -LiteralPath $hashFile) {
    Copy-Item -LiteralPath $hashFile -Destination (Join-Path $stage "sha256sums.txt") -Force
  }

  # Optional folders
  $opt = @("snapshots","reports","logs")
  foreach ($d in $opt) {
    $src = Join-Path $RunDir $d
    if (Test-Path -LiteralPath $src) {
      $dst = Join-Path $stage $d
      New-Item -ItemType Directory -Force -Path $dst | Out-Null
      Copy-Item -LiteralPath (Join-Path $src "*") -Destination $dst -Recurse -Force -ErrorAction SilentlyContinue
      Audit-Append -RunDir $RunDir -Engine "package" -EventType "STAGED_DIR" -Action "copy" -Subject $d -Details @{ from=$src; to=$dst }
    }
  }

  # ---- ZIP (PS5.1 SAFE) ----
  Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
  if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

  [System.IO.Compression.ZipFile]::CreateFromDirectory(
    $stage,
    $zipPath,
    [System.IO.Compression.CompressionLevel]::Optimal,
    $false
  )

  # Bundle manifest
  $bundleManifestPath = Join-Path $artDir "bundle.v1.manifest.json"
  $zipSha = Get-Sha256 -Path $zipPath

  $bundle = [ordered]@{
    bundle_version = "1"
    run_id         = $runId
    created_at_utc = ([DateTime]::UtcNow.ToString("o"))
    zip_file       = (Split-Path -Leaf $zipPath)
    zip_sha256     = $zipSha
    includes       = [ordered]@{
      files = @("manifest.v1.json","entitlements.v1.json","audit.v1.jsonl","sha256sums.txt")
      dirs  = $opt
    }
  }

  Write-Json -Obj $bundle -Path $bundleManifestPath

  Audit-Append -RunDir $RunDir -Engine "package" -EventType "BUNDLE_CREATED" -Action "zip" -Subject $zipName -Details @{
    zip_path        = $zipPath
    zip_sha256      = $zipSha
    bundle_manifest = (Split-Path -Leaf $bundleManifestPath)
  }

  # Reseal AFTER artifacts exist
  Seal-Run -RunDir $RunDir

  Audit-Append -RunDir $RunDir -Engine "package" -EventType "JOB_FINISHED" -Action "package" -Subject $zipName -Details @{
    artifacts_dir = $artDir
    sealed        = "sha256sums.txt"
  }

  Write-Host ("PACKAGED OK: {0}" -f $zipPath) -ForegroundColor Green
  Write-Host ("BUNDLE MAN: {0}" -f $bundleManifestPath) -ForegroundColor DarkGray
  Write-Host ("SEALED    : {0}" -f (Join-Path $RunDir "sha256sums.txt")) -ForegroundColor DarkGray
}
catch {
  # Guaranteed-safe under StrictMode because vars are defined up top
  try {
    Audit-Append -RunDir $RunDir -Engine "package" -EventType "JOB_FAILED" -Action "package" -Subject $zipName -Result "error" -Details @{
      message = $_.Exception.Message
      stage   = $stage
      zipPath = $zipPath
    }
  } catch {}
  throw
}
finally {
  try { if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force } } catch {}
}
