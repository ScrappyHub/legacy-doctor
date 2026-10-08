param([Parameter(Mandatory=$true)][string]$RepoRoot)
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
function Die([string]$Code,[string]$Detail){ throw ($Code + ":" + $Detail) }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$lane = Join-Path $RepoRoot "scripts\storage\ld_capacity_test_v1.ps1"
$self = Join-Path $RepoRoot "scripts\selftest\_selftest_ld_capacity_test_v1.ps1"
$schema = Join-Path $RepoRoot "schemas\ld.device.capacity_test.receipt.v1.json"
foreach($f in @($lane,$self)){
  if(-not (Test-Path -LiteralPath $f -PathType Leaf)){ Die "FILE_MISSING" $f }
  $tokens = $null; $errors = $null
  [void][Management.Automation.Language.Parser]::ParseFile($f,[ref]$tokens,[ref]$errors)
  if(@($errors).Count){ Die "PARSE_FAIL" ($f + ":" + $errors[0].Message) }
  Write-Output ("PARSE_OK: " + $f)
}
if(-not (Test-Path -LiteralPath $schema -PathType Leaf)){ Die "SCHEMA_MISSING" $schema }
Write-Output ("SCHEMA_OK: " + $schema)
$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $self -RepoRoot $RepoRoot
if($LASTEXITCODE -ne 0){ Die "SELFTEST_EXIT" ([string]$LASTEXITCODE) }
$text = $out -join "`n"
Write-Output $text
if($text -notmatch "SELFTEST_LD_CAPACITY_TEST_OK"){ Die "TOKEN_MISSING" "" }
Write-Output "LEGACY_DOCTOR_CAPACITY_TEST_GREEN"
