param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function Parse-GateFile([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "PARSE_GATE_MISSING" $Path
  }
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  if($err -and $err.Count -gt 0){
    $e = $err[0]
    Die "PARSE_GATE_FAIL" ($Path + ":" + $e.Extent.StartLineNumber + ":" + $e.Extent.StartColumnNumber + ": " + $e.Message)
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$Files = @(
  (Join-Path $RepoRoot "scripts\storage\_lib_ld_acquire_v1.ps1"),
  (Join-Path $RepoRoot "scripts\storage\ld_backup_device_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_backup_device_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_backup_device_physical_guard_v1.ps1")
)

foreach($p in $Files){
  Parse-GateFile $p
  Write-Output ("PARSE_OK: " + $p)
}

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

$Selftests = @(
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_backup_device_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_backup_device_physical_guard_v1.ps1")
)

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

Write-Output "LEGACY_DOCTOR_BACKUP_DEVICE_ALL_GREEN"
