param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die($c,$d){ throw ($c + ":" + $d) }

function Read([string]$p){
  if(-not (Test-Path $p)){ Die "MISSING" $p }
  [IO.File]::ReadAllText($p,[Text.UTF8Encoding]::new($false))
}

function Write([string]$p,[string]$t){
  $dir = Split-Path -Parent $p
  if($dir -and -not (Test-Path $dir)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = $t -replace "`r`n","`n" -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($p,$t,[Text.UTF8Encoding]::new($false))
}

function Parse([string]$p){
  [ScriptBlock]::Create((Get-Content -Raw $p)) | Out-Null
}

$RepoRoot = (Resolve-Path $RepoRoot).Path
$Target = Join-Path $RepoRoot "scripts\storage\ld_verify_image_v1.ps1"

$text = Read $Target

# Find receipt append block (simple replace approach)
$old = 'Append-Utf8NoBomLf'

if(-not $text.Contains($old)){
  Die "APPEND_FUNCTION_NOT_FOUND" ""
}

# Replace with safe inline append that ALWAYS ensures dir exists
$new = @'
function LD-SafeAppend([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = $Text -replace "`r`n","`n" -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::AppendAllText($Path,$t,[Text.UTF8Encoding]::new($false))
}
'@

# inject helper at top
$text = $new + "`n" + $text

# replace usage
$text = $text -replace 'Append-Utf8NoBomLf','LD-SafeAppend'

Write $Target $text
Parse $Target

Write-Host "PATCH_OK: VERIFY_IMAGE_RECEIPT_FIXED" -ForegroundColor Green