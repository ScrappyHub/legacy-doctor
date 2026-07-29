param([Parameter(Mandatory=$true)][string]$RepoRoot)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die($c,$d){ throw ($c+":"+$d) }

$RepoRoot = (Resolve-Path $RepoRoot).Path
$Target = Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_tier0_full_green_v1.ps1"

if(-not (Test-Path $Target)){
  Die "TARGET_MISSING" $Target
}

$text = Get-Content -Raw -LiteralPath $Target -Encoding UTF8

$old = @'
foreach($runner in $Runners){
  $name = Split-Path -Leaf $runner
  [void]$AllOutput.Add(("RUNNER_START: " + $runner))

  $out = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $runner -RepoRoot $RepoRoot 2>&1
  $joined = (@(@($out)) -join "`n")
  $exitCode = $LASTEXITCODE

  foreach($line in @(@($out))){
    [void]$AllOutput.Add([string]$line)
  }

  if($exitCode -ne 0){
    Write-Utf8NoBomLf $StdoutPath (@($AllOutput) -join "`n")
    Write-Utf8NoBomLf $StderrPath ("RUNNER_FAIL: " + $runner + "`nEXIT_CODE=" + $exitCode)
    Die "RUNNER_FAIL" ($name + " exit=" + $exitCode)
  }

  if($joined -notmatch "FULL_GREEN"){
    Write-Utf8NoBomLf $StdoutPath (@($AllOutput) -join "`n")
    Write-Utf8NoBomLf $StderrPath ("RUNNER_MISSING_FULL_GREEN: " + $runner)
    Die "RUNNER_MISSING_FULL_GREEN" $name
  }

  [void]$ResultRows.Add([ordered]@{
    runner = $name
    ok = $true
  })
}
'@

$new = @'
foreach($runner in $Runners){
  $name = Split-Path -Leaf $runner
  [void]$AllOutput.Add(("RUNNER_START: " + $runner))

  $rawOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $runner -RepoRoot $RepoRoot 2>&1
  $exitCode = $LASTEXITCODE

  $lines = @()
  if($rawOut -is [System.Array]){
    foreach($x in $rawOut){ $lines += [string]$x }
  } elseif($null -ne $rawOut){
    $lines += [string]$rawOut
  }

  $joined = ($lines -join "`n")

  foreach($line in $lines){
    [void]$AllOutput.Add($line)
  }

  if($exitCode -ne 0){
    Write-Utf8NoBomLf $StdoutPath ($AllOutput -join "`n")
    Write-Utf8NoBomLf $StderrPath ("RUNNER_FAIL: " + $runner + "`nEXIT_CODE=" + $exitCode)
    Die "RUNNER_FAIL" ($name + " exit=" + $exitCode)
  }

  if($joined -notmatch "FULL_GREEN"){
    Write-Utf8NoBomLf $StdoutPath ($AllOutput -join "`n")
    Write-Utf8NoBomLf $StderrPath ("RUNNER_MISSING_FULL_GREEN: " + $runner)
    Die "RUNNER_MISSING_FULL_GREEN" $name
  }

  [void]$ResultRows.Add([ordered]@{
    runner = $name
    ok = $true
  })
}
'@

if(-not $text.Contains($old)){
  Die "PATCH_TARGET_NOT_FOUND" "runner loop block"
}

$text = $text.Replace($old,$new)

$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($Target,$text,$enc)

# parse gate
$null = [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $Target -Encoding UTF8))

Write-Host ("PATCH_OK TARGET=" + $Target) -ForegroundColor Green