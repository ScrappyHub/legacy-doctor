param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Read-Utf8([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die ("MISSING_FILE: " + $Path)
  }
  return [IO.File]::ReadAllText($Path,[Text.UTF8Encoding]::new($false))
}

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

$text = Read-Utf8 $Target

$old = @'
# --- RANGE VALIDATION ---
if($manifest.byte_ranges){

  foreach($r in $manifest.byte_ranges){

    if(($r.offset -lt 0) -or ($r.length -le 0)){
      Die "LD_VERIFY_FAIL:INVALID_RANGE"
    }

    $fileSize = (Get-Item $ImagePath).Length

    if(($r.offset + $r.length) -gt $fileSize){
      Die "LD_VERIFY_FAIL:RANGE_OUT_OF_BOUNDS"
    }
  }
}
'@

$new = @'
# --- RANGE VALIDATION ---
$hasByteRanges = $false
if($manifest -and $manifest.PSObject -and $manifest.PSObject.Properties){
  $hasByteRanges = (@($manifest.PSObject.Properties.Name) -contains "byte_ranges")
}

if($hasByteRanges -and $null -ne $manifest.byte_ranges){

  foreach($r in @($manifest.byte_ranges)){

    if(($r.offset -lt 0) -or ($r.length -le 0)){
      Die "LD_VERIFY_FAIL:INVALID_RANGE"
    }

    $fileSize = (Get-Item $ImagePath).Length

    if(($r.offset + $r.length) -gt $fileSize){
      Die "LD_VERIFY_FAIL:RANGE_OUT_OF_BOUNDS"
    }
  }
}
'@

if(-not $text.Contains($old)){
  Die "PATCH_TARGET_NOT_FOUND: range validation block"
}

$text = $text.Replace($old,$new)

Write-Utf8NoBomLf $Target $text
Parse-Gate $Target
Write-Host "PATCH_OK: LD_VERIFY_IMAGE_OPTIONAL_BYTERANGES" -ForegroundColor Green