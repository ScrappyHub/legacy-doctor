param([Parameter(Mandatory=$true)][string]$RepoRoot)
Set-StrictMode -Version Latest;$ErrorActionPreference="Stop"
function Die([string]$Code,[string]$Detail){throw($Code+":"+$Detail)}
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
function ParseFile([string]$Path){$t=$null;$e=$null;[void][Management.Automation.Language.Parser]::ParseFile($Path,[ref]$t,[ref]$e);if($e.Count){throw("PARSE_FAIL:"+$Path+":"+$e[0].Message)};Write-Output ("PARSE_OK: "+$Path)}
$files=@((Join-Path $RepoRoot "scripts\storage\ld_bounded_copy_executor_dry_run_harness_v1.ps1"),(Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage03_bounded_copy_executor_dry_run_harness_v1.ps1"));foreach($file in $files){if(-not(Test-Path -LiteralPath $file -PathType Leaf)){Die "FILE_MISSING" $file};ParseFile $file}
$schema=Join-Path $RepoRoot "schemas\ld.device.bounded_copy_executor_dry_run_harness.receipt.v1.json";if(-not(Test-Path -LiteralPath $schema -PathType Leaf)){Die "SCHEMA_MISSING" $schema};Write-Output ("SCHEMA_OK: "+$schema)
$selftest=Join-Path $RepoRoot "scripts\selftest\_selftest_ld_storage03_bounded_copy_executor_dry_run_harness_v1.ps1";$out=& powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $selftest -RepoRoot $RepoRoot;if($LASTEXITCODE-ne0){Die "SELFTEST_EXIT_NONZERO" ([string]$LASTEXITCODE)};$text=$out-join"`n";Write-Output $text;if($text-notmatch"SELFTEST_LD_STORAGE03_BOUNDED_COPY_EXECUTOR_DRY_RUN_HARNESS_OK"){Die "SELFTEST_TOKEN_MISSING" ""};Write-Output "LEGACY_DOCTOR_STORAGE03_BOUNDED_COPY_EXECUTOR_DRY_RUN_HARNESS_GREEN"
