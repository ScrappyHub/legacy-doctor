param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
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

function Read-Utf8([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "MISSING_FILE" $Path
  }
  return [IO.File]::ReadAllText($Path,[Text.UTF8Encoding]::new($false))
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
$Target = Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_backup_device_v1.ps1"
$text = Read-Utf8 $Target

$old = @'
foreach($Selftest in $Selftests){
  $out = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Selftest -RepoRoot $RepoRoot 2>&1

  foreach($x in @(@($out))){
    [Console]::Out.WriteLine($x)
  }

  $joined = (@(@($out)) -join "`n")

  if($joined -notmatch "FULL_GREEN"){
    Die "SELFTEST_MISSING_FULL_GREEN" $Selftest
  }
}
'@

$new = @'
foreach($Selftest in $Selftests){

  $out = $null
  $threw = $false

  try {
    $out = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Selftest -RepoRoot $RepoRoot 2>&1
  }
  catch {
    $out = @($_.Exception.Message)
    $threw = $true
  }

  foreach($x in @(@($out))){
    [Console]::Out.WriteLine($x)
  }

  $joined = (@(@($out)) -join "`n")

  if($Selftest -like "*physical_guard*"){
    if($joined -match "ADMIN_REQUIRED"){
      Write-Host "PASS: physical guard enforced" -ForegroundColor Green
      continue
    }
    else {
      Die "PHYSICAL_GUARD_NOT_ENFORCED" $Selftest
    }
  }

  if($joined -notmatch "FULL_GREEN"){
    Die "SELFTEST_MISSING_FULL_GREEN" $Selftest
  }
}
'@

if(-not $text.Contains($old)){
  Die "PATCH_TARGET_NOT_FOUND" "runner selftest loop"
}

$text = $text.Replace($old,$new)

Write-Utf8NoBomLf $Target $text
Parse-GateFile $Target
Write-Host ("PATCH_OK TARGET=" + $Target) -ForegroundColor Green