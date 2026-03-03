param(
  [string]$Workflow = "integrity-audit",
  [string[]]$Targets = @(),
  [string]$Tier = "pro",
  [string]$RunRoot = "",
  [switch]$NoSealOnInit
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot "..\lib\doctor-common.ps1")

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path

# Default run root:
# - Windows: %LOCALAPPDATA%\LegacyDoctor\runs
# - Cross-platform later: ~/.local/share/LegacyDoctor/runs (we'll lock that next)
if ([string]::IsNullOrWhiteSpace($RunRoot)) {
  $base = Join-Path $env:LOCALAPPDATA "LegacyDoctor\runs"
  $RunRoot = $base
}

$runId  = New-RunId -Prefix "LD"
$runDir = Ensure-Dir -Path (Join-Path $RunRoot $runId)

# canonical subdirs
Ensure-Dir -Path (Join-Path $runDir "artifacts")  | Out-Null
Ensure-Dir -Path (Join-Path $runDir "logs")       | Out-Null
Ensure-Dir -Path (Join-Path $runDir "snapshots")  | Out-Null
Ensure-Dir -Path (Join-Path $runDir "reports")    | Out-Null

# entitlements — canonical v1 (we’ll plug real licensing validation later)
$ent = [ordered]@{
  license_id   = "DEV-UNLICENSED"
  tier         = $Tier
  capabilities = [ordered]@{
    "inventory.read"     = $true
    "acquire.file_copy"  = $true
    "acquire.block_image"= $false
    "transform.convert"  = $true
    "package.compress"   = $true
    "crypto.encrypt"     = $true
    "cloud.upload"       = $false
    "image.restore"      = $false
  }
  limits = [ordered]@{
    max_parallel_jobs = 1
    max_storage_gb    = 0
  }
  policy_hash = "sha256:dev"
}

$manifest = [ordered]@{
  run_id     = $runId
  started_at = ([DateTime]::UtcNow.ToString("o"))
  ended_at   = $null
  tool       = [ordered]@{
    name    = "legacy-doctor"
    version = "0.1.0"
    commit  = ""
  }
  host       = [ordered]@{
    os       = $env:OS
    hostname = $env:COMPUTERNAME
    user     = $env:USERNAME
  }
  request    = [ordered]@{
    workflow = $Workflow
    targets  = $Targets
    options  = [ordered]@{}
  }
  engine_versions = [ordered]@{
    inventory = "1.0"
    acquire   = "1.0"
    verify    = "1.0"
    package   = "1.0"
  }
}

Write-Json -Obj $manifest -Path (Join-Path $runDir "manifest.v1.json")
Write-Json -Obj $ent      -Path (Join-Path $runDir "entitlements.v1.json")

# audit file exists immediately (append-only)
New-Item -ItemType File -Force -Path (Join-Path $runDir "audit.v1.jsonl") | Out-Null

Audit-Append -RunDir $runDir -Engine "orchestrator" -EventType "RUN_START" -Action $Workflow -Subject ($Targets -join ";") -Details @{
  repo = $repoRoot
  run_root = $RunRoot
}

if (-not $NoSealOnInit) {
  Seal-Run -RunDir $runDir
}

# Print run dir for orchestration
Write-Output $runDir
