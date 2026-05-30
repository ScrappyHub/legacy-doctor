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

$target = Join-Path $RepoRoot "scripts\selftest\_selftest_ld_packetize_backup_v1.ps1"

if(-not (Test-Path $target)){
  Die "TARGET_NOT_FOUND"
}

$text = Get-Content -Raw -LiteralPath $target -Encoding UTF8

if(-not $text.Contains('$PID')){
  Die "PATCH_TARGET_NOT_FOUND:PID_NOT_PRESENT"
}

# Replace ALL occurrences safely
$text = $text.Replace('$PID','$PacketId')

Write-Utf8NoBomLf $target $text
Parse-Gate $target

Write-Host "PATCH_OK: PID_VARIABLE_COLLISION_FIXED" -ForegroundColor Green