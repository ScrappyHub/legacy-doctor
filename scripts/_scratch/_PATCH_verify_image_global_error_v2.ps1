param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function Read-Utf8([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "MISSING_FILE" $Path
  }
  return [IO.File]::ReadAllText($Path,[Text.UTF8Encoding]::new($false))
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }

  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }

  [IO.File]::WriteAllText($Path,$t,[Text.UTF8Encoding]::new($false))
}

function Parse-GateFile([string]$Path){
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)

  if($err -and $err.Count -gt 0){
    $e = $err[0]
    Die "PARSE_GATE_FAIL" ($Path + ":" + $e.Extent.StartLineNumber + ":" + $e.Extent.StartColumnNumber + ": " + $e.Message)
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Target = Join-Path $RepoRoot "scripts\storage\ld_verify_image_v1.ps1"

$text = Read-Utf8 $Target

if($text -match 'VERIFY_IMAGE_GLOBAL_ERROR_VISIBLE_V2'){
  Write-Host "ALREADY_PATCHED: VERIFY_IMAGE_GLOBAL_ERROR_VISIBLE_V2" -ForegroundColor Yellow
  exit 0
}

$prefix = @'
# VERIFY_IMAGE_GLOBAL_ERROR_VISIBLE_V2
try {
'@

$suffix = @'
}
catch {
  throw ("VERIFY_IMAGE_GLOBAL_ERROR_REAL:" + $_.Exception.Message)
}
'@

$wrapped = $prefix + "`n" + $text + "`n" + $suffix

Write-Utf8NoBomLf $Target $wrapped
Parse-GateFile $Target

Write-Host "PATCH_OK: VERIFY_IMAGE_GLOBAL_ERROR_VISIBLE_V2" -ForegroundColor Green