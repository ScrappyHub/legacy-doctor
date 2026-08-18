param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$FormatScript = Join-Path $RepoRoot "scripts\storage\ld_format_fat32_owned_v1.ps1"

if(-not (Test-Path -LiteralPath $FormatScript -PathType Leaf)){
  Die "FORMAT_SCRIPT_MISSING" $FormatScript
}

$tokens = $null
$errors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($FormatScript,[ref]$tokens,[ref]$errors)
if(@($errors).Count -gt 0){
  Die "FORMAT_SCRIPT_PARSE_FAILED" $errors[0].Message
}

$previousErrorAction = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
  $out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $FormatScript `
    -RepoRoot $RepoRoot `
    -DiskNumber 0 `
    -IUnderstand "ERASE_DISK_0" 2>&1
  $exitCode = $LASTEXITCODE
} finally {
  $ErrorActionPreference = $previousErrorAction
}
$text = (@($out | ForEach-Object { [string]$_ }) -join "`n")

if($exitCode -eq 0){
  Die "QUARANTINE_BYPASSED" "formatter returned success"
}
if($text -notmatch "CAPABILITY_QUARANTINED"){
  Die "QUARANTINE_TOKEN_MISSING" $text
}
if($text -match "FORMAT_FAT32_OWNED_OK"){
  Die "FALSE_SUCCESS_TOKEN" $text
}

Write-Output "PASS: destructive formatter is quarantined before device access"
Write-Output "SELFTEST_LD_FAT32_OWNED_WRITEPATH_QUARANTINED_OK"
Write-Output "FULL_GREEN"
