param([Parameter(Mandatory=$true)][string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Selftest = Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage_v1.ps1"
if(-not (Test-Path -LiteralPath $Selftest -PathType Leaf)){ throw ("MISSING: " + $Selftest) }
$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source
Write-Host ("RUN: " + $Selftest) -ForegroundColor Yellow
$out = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Selftest -RepoRoot $RepoRoot
foreach($x in @(@($out))){ [Console]::Out.WriteLine($x) }
if((@(@($out)) -join "`n") -notmatch "FULL_GREEN"){ throw "SELFTEST_MISSING_FULL_GREEN" }
Write-Output "FULL_GREEN"
