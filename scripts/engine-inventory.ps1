param(
  [Parameter(Mandatory=$true)][string]$RunDir,
  [string[]]$Targets = @()
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "..\lib\doctor-common.ps1")

Audit-Append -RunDir $RunDir -Engine "inventory" -EventType "JOB_STARTED" -Action "inventory" -Subject ($Targets -join ";") -Details @{}

# For now: snapshot minimal info (cross-platform friendly later)
$snapDir = Join-Path $RunDir "snapshots"
$ts = Get-Date -Format "yyyyMMdd_HHmmss"
$out = Join-Path $snapDir ("inventory_" + $ts + ".txt")

$lines = @()
$lines += "ts=$ts"
$lines += "targets=" + ($Targets -join ";")
$lines += "user=" + $env:USERNAME
$lines += "machine=" + $env:COMPUTERNAME
$lines += "os=" + $env:OS
$lines | Set-Content -LiteralPath $out -Encoding UTF8

Audit-Append -RunDir $RunDir -Engine "inventory" -EventType "SNAPSHOT_TAKEN" -Action "write" -Subject $out -Details @{ file = (Split-Path -Leaf $out) }
Audit-Append -RunDir $RunDir -Engine "inventory" -EventType "JOB_FINISHED" -Action "inventory" -Subject ($Targets -join ";") -Details @{ snapshot = (Split-Path -Leaf $out) }

Write-Output $out
