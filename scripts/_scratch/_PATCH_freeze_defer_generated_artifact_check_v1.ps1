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
$Target = Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_tier0_freeze_v1.ps1"

$text = Read-Utf8 $Target

if($text -match 'ARTIFACT_DEFERRED'){
  Write-Host "ALREADY_PATCHED: FREEZE_DEFER_GENERATED_ARTIFACT" -ForegroundColor Yellow
  exit 0
}

$old = @'
foreach($p in @($ArtifactsToHash)){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
    Die "ARTIFACT_MISSING" $p
  }
  Write-Output ("ARTIFACT_OK: " + $p)
}
'@

$new = @'
$DeferredArtifacts = @(
  (Join-Path $RepoRoot "proofs\acquire\selftest_inputs\synthetic_source.bin")
)

foreach($p in @($ArtifactsToHash)){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
    if(@($DeferredArtifacts) -contains $p){
      Write-Output ("ARTIFACT_DEFERRED: " + $p)
      continue
    }

    Die "ARTIFACT_MISSING" $p
  }

  Write-Output ("ARTIFACT_OK: " + $p)
}
'@

if(-not $text.Contains($old)){
  Die "PATCH_TARGET_NOT_FOUND" "artifact precheck block"
}

$text = $text.Replace($old,$new)

Write-Utf8NoBomLf -Path $Target -Text $text
Parse-GateFile -Path $Target

Write-Host ("PATCH_OK TARGET=" + $Target) -ForegroundColor Green