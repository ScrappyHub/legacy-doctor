param([Parameter(Mandatory=$true)][string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function Die([string]$m){ throw $m }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Storage = Join-Path $RepoRoot "scripts\storage\ld_storage_v1.ps1"
if(-not (Test-Path -LiteralPath $Storage -PathType Leaf)){ Die ("MISSING: " + $Storage) }
$ReceiptsDir = Join-Path $RepoRoot "proofs\receipts"
$ReceiptPath = Join-Path $ReceiptsDir "storage.ndjson"
$len0 = 0
if(Test-Path -LiteralPath $ReceiptPath -PathType Leaf){ $len0 = (Get-Item -LiteralPath $ReceiptPath).Length }
$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source
Write-Host ("SELFTEST: list -> " + $Storage) -ForegroundColor Yellow
& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Storage -RepoRoot $RepoRoot -Cmd list | Out-Host
if(-not (Test-Path -LiteralPath $ReceiptPath -PathType Leaf)){ Die ("RECEIPT_MISSING: " + $ReceiptPath) }
$len1 = (Get-Item -LiteralPath $ReceiptPath).Length
if($len1 -le $len0){ Die ("RECEIPT_NOT_APPENDED: before=" + $len0 + " after=" + $len1) }

Write-Host "SELFTEST_OK" -ForegroundColor Green
Write-Output "FULL_GREEN"
