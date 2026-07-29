param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $t = $Text -replace "`r`n","`n" -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($Path,$t,[Text.UTF8Encoding]::new($false))
}

function Parse-Gate([string]$Path){
  $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
  [ScriptBlock]::Create($raw) | Out-Null
}

$target = Join-Path $RepoRoot "scripts\_RUN_ld_tier0_selftest_v1.ps1"

if(-not (Test-Path $target)){
  Die "TARGET_NOT_FOUND"
}

$text = Get-Content -Raw -LiteralPath $target -Encoding UTF8

# Replace tamper execution block
$pattern = 'RUN: tamper test[\s\S]*?LD_SELFTEST_FAIL:VERIFY_TOKEN_MISSING'

$replacement = @'
RUN: tamper test

$err = $null
$out3 = $null

try {
  $out3 = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $VerifyScript `
    -RepoRoot $RepoRoot `
    -ImagePath $img `
    -ManifestPath $man 2>&1
}
catch {
  $out3 = $_.Exception.Message
}

$joined3 = ($out3 | Out-String)

if($joined3 -notmatch "LD_VERIFY_FAIL:SHA256_MISMATCH"){
  Die "LD_SELFTEST_FAIL:TAMPER_NOT_DETECTED"
}

Write-Host "PASS: tamper detection" -ForegroundColor Green

LD_SELFTEST_FAIL:VERIFY_TOKEN_MISSING
'@

if(-not [regex]::IsMatch($text,$pattern)){
  Die "PATCH_TARGET_NOT_FOUND: tamper block"
}

$text = [regex]::Replace($text,$pattern,$replacement)

Write-Utf8NoBomLf $target $text
Parse-Gate $target

Write-Host "PATCH_OK: TIER0_VERIFY_CAPTURE_FIXED" -ForegroundColor Green