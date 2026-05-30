# =====================================================================
# PATCH: widen -Cmd ValidateSet to include "inspect"
# Target: scripts\storage\ld_storage_v1.ps1
# Sentinel: LD_STORAGE_CMD_VALIDATESET_V1
# =====================================================================
param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Utf8NoBom(){ New-Object System.Text.UTF8Encoding($false) }
function ParseGateFile([string]$path){
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){ throw ("PARSE_GATE_MISSING: " + $path) }
  $tok=$null; $err=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tok,[ref]$err)
  if($err -and $err.Count -gt 0){
    $e=$err[0]
    throw ("PARSE_GATE_FAIL: {0}:{1}:{2}: {3}" -f $path,$e.Extent.StartLineNumber,$e.Extent.StartColumnNumber,$e.Message)
  }
}
function WriteUtf8NoBomLf([string]$path,[string]$text){
  $dir = Split-Path -Parent $path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = ($text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($path,$t,(Utf8NoBom))
  if(-not (Test-Path -LiteralPath $path -PathType Leaf)){ throw ("WRITE_FAILED: " + $path) }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Target = Join-Path $RepoRoot "scripts\storage\ld_storage_v1.ps1"
if(-not (Test-Path -LiteralPath $Target -PathType Leaf)){ throw ("MISSING_TARGET: " + $Target) }

$src = [IO.File]::ReadAllText($Target,(Utf8NoBom))
$src = ($src -replace "`r`n","`n") -replace "`r","`n"

if($src -match 'LD_STORAGE_CMD_VALIDATESET_V1'){
  Write-Output ("OK: already patched (LD_STORAGE_CMD_VALIDATESET_V1) target=" + $Target)
  exit 0
}

# We patch ONLY the -Cmd parameter ValidateSet list.
# Match: [ValidateSet("list","format")] [string]$Cmd  (whitespace/newlines allowed)
$pattern = '(?s)(\[Parameter\(\s*Mandatory\s*=\s*\$true\s*\)\]\s*\[\s*ValidateSet\(\s*("list"\s*,\s*"format"(?:\s*,\s*"inspect")?)\s*\)\s*\]\s*\[\s*string\s*\]\s*\$Cmd)'
$m = [regex]::Match($src,$pattern)
if(-not $m.Success){
  # fallback: find ValidateSet("list","format") nearest $Cmd
  $pattern2 = '(?s)(ValidateSet\(\s*"list"\s*,\s*"format"\s*(?:,\s*"inspect"\s*)?\))(\s*\]\s*\[\s*string\s*\]\s*\$Cmd)'
  $m2 = [regex]::Match($src,$pattern2)
  if(-not $m2.Success){
    throw "PATCH_FAIL_CMD_VALIDATESET_NOT_FOUND"
  }
  $old = $m2.Groups[1].Value
  if($old -match '"inspect"'){
    # already widened but sentinel missing; just add sentinel
    $src = "# LD_STORAGE_CMD_VALIDATESET_V1`n" + $src
  } else {
    $new = 'ValidateSet("list","format","inspect")'
    $src = [regex]::Replace($src,[regex]::Escape($old),$new,1)
    $src = "# LD_STORAGE_CMD_VALIDATESET_V1`n" + $src
  }
} else {
  $whole = $m.Groups[1].Value
  if($whole -match '"inspect"'){
    $src = "# LD_STORAGE_CMD_VALIDATESET_V1`n" + $src
  } else {
    # replace inside ValidateSet to add inspect
    $src2 = $src
    $src2 = $src2.Replace('ValidateSet("list","format")','ValidateSet("list","format","inspect")')
    # also handle spaced variants via regex if not replaced
    if($src2 -eq $src){
      $src2 = [regex]::Replace($src2,'ValidateSet\(\s*"list"\s*,\s*"format"\s*\)','ValidateSet("list","format","inspect")',1)
    }
    $src = "# LD_STORAGE_CMD_VALIDATESET_V1`n" + $src2
  }
}

WriteUtf8NoBomLf $Target $src
ParseGateFile $Target
Write-Output ("PATCH_OK LD_STORAGE_CMD_VALIDATESET_V1 target=" + $Target)