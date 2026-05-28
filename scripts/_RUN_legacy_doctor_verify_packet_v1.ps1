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
  (Join-Path $RepoRoot "scripts\storage\ld_verify_packet_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_verify_packet_v1.ps1")
)

foreach($p in $Files){
  Parse-GateFile $p
  Write-Output ("PARSE_OK: " + $p)
}

$Selftest = Join-Path $RepoRoot "scripts\selftest\_selftest_ld_verify_packet_v1.ps1"
$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

$out = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Selftest -RepoRoot $RepoRoot 2>&1

foreach($x in @(@($out))){
  [Console]::Out.WriteLine($x)
}

$joined = (@(@($out)) -join "`n")

if($joined -notmatch "FULL_GREEN"){
  Die "SELFTEST_MISSING_FULL_GREEN" $Selftest
}
if($joined -notmatch "SELFTEST_LD_VERIFY_PACKET_OK"){
  Die "SELFTEST_MISSING_OK" $Selftest
}

Write-Output "LEGACY_DOCTOR_VERIFY_PACKET_ALL_GREEN"