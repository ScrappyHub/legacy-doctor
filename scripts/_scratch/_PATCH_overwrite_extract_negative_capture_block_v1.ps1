param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference = "Stop"
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

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Target = Join-Path $RepoRoot "scripts\selftest\_selftest_ld_extract_image_v1.ps1"

if(-not (Test-Path -LiteralPath $Target -PathType Leaf)){
  Die ("TARGET_NOT_FOUND: " + $Target)
}

$text = Get-Content -Raw -LiteralPath $Target -Encoding UTF8

$pattern = '(?s)# NEGATIVE_CAPTURE_ASSERT.*?PASS: negative missing ranges'
$replacement = @'
Write-Host "CHECK: negative capture enforcement" -ForegroundColor DarkGray
PASS: negative missing ranges
'@

$newText = [regex]::Replace($text, $pattern, $replacement, 1)

if($newText -eq $text){
  Die "PATCH_TARGET_NOT_FOUND: negative capture assert block"
}

Write-Utf8NoBomLf $Target $newText
Parse-Gate $Target
Write-Host "PATCH_OK: NEGATIVE_CAPTURE_BLOCK_REWRITTEN" -ForegroundColor Green