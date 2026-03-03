param([Parameter(Mandatory=$true)][string]$Scorer)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
$bak = ($Scorer + ".bak")
if(-not (Test-Path -LiteralPath $Scorer)) { throw ("MISSING_SCORER: " + $Scorer) }
if(-not (Test-Path -LiteralPath $bak))    { throw ("MISSING_BAK: " + $bak) }
Copy-Item -LiteralPath $bak -Destination $Scorer -Force
# Parse-check restored scorer
[ScriptBlock]::Create((Get-Content -Raw -LiteralPath $Scorer)) | Out-Null
Write-Host ("RESTORED + PARSE OK: {0}" -f $Scorer) -ForegroundColor Green