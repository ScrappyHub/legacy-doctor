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
  Die "TARGET_NOT_FOUND"
}

$lines = Get-Content -LiteralPath $target -Encoding UTF8

$anchorIndex = -1

for($i=0; $i -lt $lines.Count; $i++){
  if($lines[$i] -match 'PASS: byte range extract'){
    $anchorIndex = $i
    break
  }
}

if($anchorIndex -lt 0){
  Die "ANCHOR_NOT_FOUND"
}

# Next line should be the broken one
$targetIndex = $anchorIndex + 1

if($targetIndex -ge $lines.Count){
  Die "TARGET_LINE_OUT_OF_RANGE"
}

# Replace ONLY that line
$lines[$targetIndex] = 'Write-Host "CHECK: negative capture enforcement" -ForegroundColor DarkGray'

$new = ($lines -join "`n")

Write-Utf8NoBomLf $target $new
Parse-Gate $target

Write-Host "PATCH_OK: NEGATIVE_CAPTURE_LINE_FIXED" -ForegroundColor Green