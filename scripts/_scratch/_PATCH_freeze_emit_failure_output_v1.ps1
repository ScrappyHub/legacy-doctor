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
  $t = $Text -replace "`r`n","`n" -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($Path,$t,[Text.UTF8Encoding]::new($false))
}

function Parse-Gate([string]$Path){
  $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
  [ScriptBlock]::Create($raw) | Out-Null
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Target = Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_tier0_freeze_v1.ps1"
$text = Read-Utf8 $Target

$old = @'
  if($proc.ExitCode -ne 0){
    Write-Utf8NoBomLf -Path $StdoutPath -Text ($stdoutLines -join "`n")
    Write-Utf8NoBomLf -Path $StderrPath -Text ($stderrLines -join "`n")
    Die "RUNNER_EXIT_NONZERO" ($runner.name + ":" + [string]$proc.ExitCode)
  }
'@

$new = @'
  if($proc.ExitCode -ne 0){
    Write-Utf8NoBomLf -Path $StdoutPath -Text ($stdoutLines -join "`n")
    Write-Utf8NoBomLf -Path $StderrPath -Text ($stderrLines -join "`n")

    Write-Host ("FREEZE_FAIL_RUNNER: " + $runner.name) -ForegroundColor Yellow
    Write-Host ("FREEZE_FAIL_EXIT: " + [string]$proc.ExitCode) -ForegroundColor Yellow

    if(-not [string]::IsNullOrWhiteSpace($outText)){
      Write-Host ("FREEZE_FAIL_STDOUT_BEGIN: " + $runner.name) -ForegroundColor Yellow
      [Console]::Out.WriteLine($outText)
      Write-Host ("FREEZE_FAIL_STDOUT_END: " + $runner.name) -ForegroundColor Yellow
    }

    if(-not [string]::IsNullOrWhiteSpace($errText)){
      Write-Host ("FREEZE_FAIL_STDERR_BEGIN: " + $runner.name) -ForegroundColor Yellow
      [Console]::Out.WriteLine($errText)
      Write-Host ("FREEZE_FAIL_STDERR_END: " + $runner.name) -ForegroundColor Yellow
    }

    Die "RUNNER_EXIT_NONZERO" ($runner.name + ":" + [string]$proc.ExitCode)
  }
'@

if(-not $text.Contains($old)){
  Die "PATCH_TARGET_NOT_FOUND" "freeze nonzero exit block"
}

$text = $text.Replace($old,$new)

Write-Utf8NoBomLf $Target $text
Parse-Gate $Target
Write-Host "PATCH_OK: FREEZE_EMITS_FAILURE_OUTPUT" -ForegroundColor Green