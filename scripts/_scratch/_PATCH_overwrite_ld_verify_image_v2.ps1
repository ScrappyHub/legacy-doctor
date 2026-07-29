param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

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
$Target = Join-Path $RepoRoot "scripts\storage\ld_verify_image_v1.ps1"

$body = @'
param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$ImagePath,
  [Parameter(Mandatory=$true)][string]$ManifestPath
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Read-Json([string]$p){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die "VERIFY_FAIL:MANIFEST_MISSING" }
  return Get-Content -Raw -LiteralPath $p -Encoding UTF8 | ConvertFrom-Json
}

function Sha256([string]$p){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){ Die "VERIFY_FAIL:IMAGE_MISSING" }
  $h = Get-FileHash -Algorithm SHA256 -LiteralPath $p
  return $h.Hash.ToLower()
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ImagePath = (Resolve-Path -LiteralPath $ImagePath).Path
$ManifestPath = (Resolve-Path -LiteralPath $ManifestPath).Path

$manifest = Read-Json $ManifestPath

if($null -eq $manifest){
  Die "VERIFY_FAIL:MANIFEST_INVALID"
}

$propNames = @()
if($manifest.PSObject -and $manifest.PSObject.Properties){
  $propNames = @($manifest.PSObject.Properties.Name)
}

if(-not ($propNames -contains 'image_sha256')){
  Die "VERIFY_FAIL:MANIFEST_INVALID"
}

$actualHash = Sha256 $ImagePath
$expectedHash = ([string]$manifest.image_sha256).ToLower()

if([string]::IsNullOrWhiteSpace($expectedHash)){
  Die "VERIFY_FAIL:MANIFEST_INVALID"
}

if($actualHash -ne $expectedHash){
  Die "LD_VERIFY_FAIL:SHA256_MISMATCH"
}

$hasByteRanges = ($propNames -contains 'byte_ranges')

if($hasByteRanges -and $null -ne $manifest.byte_ranges){
  foreach($r in @($manifest.byte_ranges)){
    if(($r.offset -lt 0) -or ($r.length -le 0)){
      Die "LD_VERIFY_FAIL:INVALID_RANGE"
    }

    $fileSize = (Get-Item -LiteralPath $ImagePath).Length

    if(($r.offset + $r.length) -gt $fileSize){
      Die "LD_VERIFY_FAIL:RANGE_OUT_OF_BOUNDS"
    }
  }
}

Write-Host "LD_VERIFY_IMAGE_OK" -ForegroundColor Green
'@

Write-Utf8NoBomLf $Target $body
Parse-Gate $Target
Write-Host "PATCH_OK: LD_VERIFY_IMAGE_REWRITTEN" -ForegroundColor Green