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

# Remove any previously half-installed generated-artifact blocks.
$text = [regex]::Replace(
  $text,
  '(?s)# FREEZE_GENERATED_ARTIFACT_LINEEDIT_V1.*?(?=\$HashLines\s*=\s*@\(\))',
  ''
)

$text = [regex]::Replace(
  $text,
  '(?s)# FREEZE_GENERATED_ARTIFACTS_AFTER_RUNNERS_V1.*?(?=\$HashTargets\s*=\s*@\()',
  ''
)

$text = [regex]::Replace(
  $text,
  '(?s)# FREEZE_SYNTHETIC_SOURCE_AFTER_RUNNERS_V3.*?(?=\$HashLines\s*=\s*@\(\))',
  ''
)

# Remove stray lines left from failed attempts.
$lines = @($text -split "`n")
$out = @()

foreach($line in @($lines)){
  if($line -match 'proofs\\acquire\\selftest_inputs\\synthetic_source\.bin'){
    continue
  }

  if($line -match 'GeneratedSyntheticSource'){
    continue
  }

  if($line -match 'GeneratedArtifactsToHash'){
    continue
  }

  if($line -match 'ArtifactsToHashFinal'){
    continue
  }

  $out += $line
}

$text = ($out -join "`n")

# Restore hash target expression if a prior patch changed it.
$text = $text.Replace(') + $ScriptsToParse + $ArtifactsToHashFinal', ') + $ScriptsToParse + $ArtifactsToHash')

# Repair trailing comma after final schema artifact if synthetic artifact removal left one.
$text = [regex]::Replace(
  $text,
  '(?m)^(\s*\(Join-Path \$RepoRoot "schemas\\ld\.packet\.verify\.receipt\.v1\.json"\)),\s*$',
  '$1'
)

# Install final generated-artifact validation immediately before hash lines are emitted.
$marker = '$HashLines = @()'
$idx = $text.IndexOf($marker)
if($idx -lt 0){
  Die "HASHLINES_MARKER_NOT_FOUND" $marker
}

$insert = @'
# FREEZE_SYNTHETIC_SOURCE_AFTER_RUNNERS_V3
$GeneratedSyntheticSource = Join-Path $RepoRoot "proofs\acquire\selftest_inputs\synthetic_source.bin"
if(-not (Test-Path -LiteralPath $GeneratedSyntheticSource -PathType Leaf)){
  Die "GENERATED_ARTIFACT_MISSING" $GeneratedSyntheticSource
}

Write-Output ("ARTIFACT_GENERATED_OK: " + $GeneratedSyntheticSource)
$HashTargets = @($HashTargets) + @($GeneratedSyntheticSource)

'@

$text = $text.Insert($idx,$insert)

Write-Utf8NoBomLf -Path $Target -Text $text
Parse-GateFile -Path $Target

Write-Host ("PATCH_OK TARGET=" + $Target) -ForegroundColor Green