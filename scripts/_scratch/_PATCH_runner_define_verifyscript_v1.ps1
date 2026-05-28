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

$target = Join-Path $RepoRoot "scripts\_RUN_ld_tier0_selftest_v1.ps1"

if(-not (Test-Path $target)){
  Die "RUNNER_NOT_FOUND"
}

$text = Get-Content -Raw -LiteralPath $target -Encoding UTF8

# --- ensure VerifyScript exists ---
if($text -notmatch '\$VerifyScript'){

  $insert = @'
$VerifyScript = Join-Path $RepoRoot "scripts\storage\ld_verify_image_v1.ps1"
'@

  # insert after RepoRoot resolve
  if($text -match '\$RepoRoot\s*=\s*\(Resolve-Path'){
    $text = $text -replace '(\$RepoRoot\s*=\s*\(Resolve-Path[^\n]+\))', "`$1`n$insert"
  } else {
    Die "ANCHOR_NOT_FOUND: RepoRoot"
  }
}

# --- fix tamper execution block ---
$text = $text -replace '\&\s*\$PSExe[^\n]+ld_verify_image_v1\.ps1', '& $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $VerifyScript'

Write-Utf8NoBomLf $target $text
Parse-Gate $target

Write-Host "PATCH_OK: VERIFY_SCRIPT_DEFINED" -ForegroundColor Green