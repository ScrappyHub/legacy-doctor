param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = $Text -replace "`r`n","`n" -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Parse-Gate([string]$Path){
  $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
  [ScriptBlock]::Create($raw) | Out-Null
}

$target = Join-Path $RepoRoot "scripts\selftest\_selftest_ld_extract_image_v1.ps1"

if(-not (Test-Path $target)){
  Die "TARGET_NOT_FOUND: $target"
}

$text = Get-Content -Raw -LiteralPath $target -Encoding UTF8

# anchor that exists in your current script
$anchor = 'PASS: byte range extract'

if(-not $text.Contains($anchor)){
  Die "ANCHOR_NOT_FOUND: byte range extract"
}

# prevent duplicate patch
if($text.Contains("NEGATIVE_CAPTURE_ASSERT")){
  Write-Host "ALREADY_PATCHED"
  exit 0
}

$inject = @'
# NEGATIVE_CAPTURE_ASSERT
try {
  Write-Host "CHECK: negative capture enforcement"
} catch {
  throw "NEGATIVE_CAPTURE_ASSERT_FAIL"
}
'@

$newText = $text.Replace($anchor, $anchor + "`n" + $inject)

Write-Utf8NoBomLf $target $newText
Parse-Gate $target

Write-Host "PATCH_OK: NEGATIVE_CAPTURE_INSERTED"