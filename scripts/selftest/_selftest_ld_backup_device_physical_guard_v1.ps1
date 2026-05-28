param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function Require([bool]$Condition,[string]$Code,[string]$Detail){
  if(-not $Condition){
    Die $Code $Detail
  }
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
$AcquireLib = Join-Path $RepoRoot "scripts\storage\_lib_ld_acquire_v1.ps1"
$BackupScript = Join-Path $RepoRoot "scripts\storage\ld_backup_device_v1.ps1"

foreach($p in @($AcquireLib,$BackupScript)){
  Parse-GateFile $p
  Write-Host ("PARSE_OK: " + $p) -ForegroundColor DarkGray
}

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$out = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $BackupScript -RepoRoot $RepoRoot -DiskNumber 0 -Mode raw_image -ChunkSizeBytes 1048576 2>&1

$joined = (@(@($out)) -join "`n")
foreach($x in @(@($out))){
  [Console]::Out.WriteLine($x)
}

Require ($joined -match "ADMIN_REQUIRED") "EXPECTED_ADMIN_GUARD_MISSING" ""
Write-Host "PASS: physical acquisition admin guard" -ForegroundColor Green
Write-Host "SELFTEST_LD_BACKUP_DEVICE_PHYSICAL_GUARD_OK" -ForegroundColor Green
Write-Output "FULL_GREEN"