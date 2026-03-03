param(
  [Parameter(Mandatory=$true)][string]$Text
)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
Set-Clipboard -Value $Text
Write-Host "CLIPBOARD SET:" -ForegroundColor Green
Write-Host $Text -ForegroundColor DarkGray
