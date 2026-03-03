param(
  [Parameter(Mandatory=$true)][string]$RunDir
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "..\lib\doctor-common.ps1")

Audit-Append -RunDir $RunDir -Engine "verify" -EventType "JOB_STARTED" -Action "verify" -Subject "run" -Details @{}

# For now: seal manifest/entitlements/audit + any artifacts
Seal-Run -RunDir $RunDir

Audit-Append -RunDir $RunDir -Engine "verify" -EventType "JOB_FINISHED" -Action "verify" -Subject "run" -Details @{ sealed="sha256sums.txt" }
