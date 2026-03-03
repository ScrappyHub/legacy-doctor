param(
  [Parameter(Mandatory=$true)][string]$RunDir,
  [string[]]$Targets = @()
)
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot "..\lib\doctor-common.ps1")

Audit-Append -RunDir $RunDir -Engine "acquire" -EventType "JOB_STARTED" -Action "acquire" -Subject ($Targets -join ";") -Details @{}

# Placeholder: real acquisition will be (file-level copy OR block image)
# For now, just record intent.
Audit-Append -RunDir $RunDir -Engine "acquire" -EventType "JOB_FINISHED" -Action "acquire" -Subject ($Targets -join ";") -Details @{ mode="placeholder" }
