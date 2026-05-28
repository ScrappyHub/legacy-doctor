param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $t = $Text -replace "`r`n","`n" -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Parse-Gate([string]$Path){
  $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
  [ScriptBlock]::Create($raw) | Out-Null
}

$target = Join-Path $RepoRoot "scripts\storage\_lib_ld_packet_v1.ps1"

if(-not (Test-Path $target)){
  Die "TARGET_NOT_FOUND"
}

$text = Get-Content -Raw -LiteralPath $target -Encoding UTF8

# Replace ANY existing PacketId logic
$pattern = 'function\s+Get-.*PacketId[\s\S]*?\}'
if(-not ($text -match $pattern)){
  Die "PACKET_ID_FUNCTION_NOT_FOUND"
}

$new = @'
function Get-LD-PacketIdFromManifestBytes([byte[]]$bytes){

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($bytes)
  } finally {
    $sha.Dispose()
  }

  return ([BitConverter]::ToString($hash) -replace "-","").ToLower()
}

function Get-LD-PacketId([string]$ManifestPath){

  if(-not (Test-Path -LiteralPath $ManifestPath)){
    throw "MANIFEST_NOT_FOUND"
  }

  # MUST read raw bytes (NOT string → NOT ConvertTo-Json)
  $bytes = [System.IO.File]::ReadAllBytes($ManifestPath)

  return Get-LD-PacketIdFromManifestBytes -bytes $bytes
}
'@

$text = [regex]::Replace($text,$pattern,$new)

Write-Utf8NoBomLf $target $text
Parse-Gate $target

Write-Host "PATCH_OK: CANONICAL_PACKET_ID" -ForegroundColor Green