param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die($c,$d){ throw ($c + ":" + $d) }

function Read($p){
  if(-not (Test-Path $p)){ Die "MISSING" $p }
  [IO.File]::ReadAllText($p,[Text.UTF8Encoding]::new($false))
}

function Write($p,$t){
  $dir = Split-Path -Parent $p
  if($dir -and -not (Test-Path $dir)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = $t -replace "`r`n","`n" -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($p,$t,[Text.UTF8Encoding]::new($false))
}

function Parse($p){
  [ScriptBlock]::Create((Get-Content -Raw $p)) | Out-Null
}

$RepoRoot = (Resolve-Path $RepoRoot).Path
$Target = Join-Path $RepoRoot "scripts\storage\ld_verify_image_v1.ps1"

$text = Read $Target

if(-not $text.Contains("VERIFY_IMAGE_GLOBAL_ERROR_VISIBLE_V2")){
  Write-Host "NOT_WRAPPED" -ForegroundColor Yellow
  exit 0
}

# Remove wrapper safely
$text = $text -replace '(?s)^# VERIFY_IMAGE_GLOBAL_ERROR_VISIBLE_V2\s*try\s*\{\s*',''
$text = $text -replace '\}\s*catch\s*\{\s*throw\s*\("VERIFY_IMAGE_GLOBAL_ERROR_REAL:.*?\)\s*\}\s*$',''

Write $Target $text
Parse $Target

Write-Host "PATCH_OK: VERIFY_IMAGE_RESTORED" -ForegroundColor Green