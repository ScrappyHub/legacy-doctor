param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Read-Utf8([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die ("MISSING_FILE: " + $Path)
  }
  return [IO.File]::ReadAllText($Path,[Text.UTF8Encoding]::new($false))
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = $Text -replace "`r`n","`n" -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($Path,$t,[Text.UTF8Encoding]::new($false))
}

function Parse-Gate([string]$Path){
  $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
  [ScriptBlock]::Create($raw) | Out-Null
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Target = Join-Path $RepoRoot "scripts\_RUN_ld_tier0_selftest_v1.ps1"

$text = Read-Utf8 $Target

$anchor = 'Write-Host "RUN: tamper test"'
$idx = $text.IndexOf($anchor)
if($idx -lt 0){
  Die "PATCH_TARGET_NOT_FOUND: RUN tamper anchor"
}

$head = $text.Substring(0,$idx)

$tail = @'
Write-Host "RUN: tamper test" -ForegroundColor Yellow

Add-Content -LiteralPath $img -Value "X"

$negOut = $null
$negText = ""

try {
  $negOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass `
    -File $VerifyScript `
    -RepoRoot $RepoRoot `
    -ImagePath $img `
    -ManifestPath $man 2>&1

  $negText = (@(@($negOut)) -join "`n")
}
catch {
  $negText = $_.Exception.Message
}

if($negOut){
  foreach($x in @(@($negOut))){
    [Console]::Out.WriteLine($x)
  }
}

if($negText -notmatch "LD_VERIFY_FAIL:SHA256_MISMATCH"){
  throw ("TAMPER_NEGATIVE_ASSERT_FAIL: " + $negText)
}

Write-Host "PASS: tamper detection" -ForegroundColor Green
Write-Host "LD_TIER0_SELFTEST_OK" -ForegroundColor Green
Write-Output "FULL_GREEN"
'@

$newText = $head + $tail

Write-Utf8NoBomLf $Target $newText
Parse-Gate $Target
Write-Host "PATCH_OK: RUNNER_TAMPER_CAPTURE_FIXED" -ForegroundColor Green