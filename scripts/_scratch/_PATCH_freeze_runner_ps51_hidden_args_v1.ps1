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

if($text -match 'function Quote-ProcessArg'){
  Write-Host "ALREADY_PATCHED: PS51_HIDDEN_ARGS" -ForegroundColor Yellow
  exit 0
}

$pattern = '(?s)\s+\$psi = New-Object System\.Diagnostics\.ProcessStartInfo.*?Write-Utf8NoBomLf -Path \$tmpErr -Text \$errText'

$replacement = @'
  function Quote-ProcessArg([string]$Value){
    if($null -eq $Value){ $Value = "" }
    return ('"' + ($Value.Replace('\','\\').Replace('"','\"')) + '"')
  }

  $args = @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    [string]$runner.path,
    "-RepoRoot",
    $RepoRoot
  )

  $argTextParts = @()
  foreach($a in @($args)){
    if($a -match '^[A-Za-z0-9_\-]+$'){
      $argTextParts += $a
    }
    else {
      $argTextParts += (Quote-ProcessArg ([string]$a))
    }
  }

  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $PSExe
  $psi.Arguments = ($argTextParts -join " ")
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.WorkingDirectory = $RepoRoot

  $proc = New-Object System.Diagnostics.Process
  $proc.StartInfo = $psi

  [void]$proc.Start()
  $outText = $proc.StandardOutput.ReadToEnd()
  $errText = $proc.StandardError.ReadToEnd()
  $proc.WaitForExit()

  Write-Utf8NoBomLf -Path $tmpOut -Text $outText
  Write-Utf8NoBomLf -Path $tmpErr -Text $errText
'@

$newText = [regex]::Replace($text,$pattern,$replacement,1)

if($newText -eq $text){
  Die "PATCH_TARGET_NOT_FOUND" "ProcessStartInfo ArgumentList block"
}

Write-Utf8NoBomLf -Path $Target -Text $newText
Parse-GateFile -Path $Target

Write-Host ("PATCH_OK TARGET=" + $Target) -ForegroundColor Green