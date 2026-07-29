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

$VerifyScript = Join-Path $RepoRoot "scripts\storage\ld_verify_packet_v1.ps1"
$PacketizeScript = Join-Path $RepoRoot "scripts\storage\ld_packetize_case_v1.ps1"
$SchemaPath = Join-Path $RepoRoot "schemas\ld.packet.verify.receipt.v1.json"

foreach($p in @($VerifyScript,$PacketizeScript)){
  Parse-GateFile $p
  Write-Host ("PARSE_OK: " + $p) -ForegroundColor DarkGray
}

Require (Test-Path -LiteralPath $SchemaPath -PathType Leaf) "MISSING_SCHEMA" $SchemaPath
Write-Host ("SCHEMA_OK: " + $SchemaPath) -ForegroundColor DarkGray

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

$img = "C:\dev\legacy-doctor\proofs\acquire\image_20260326_214243_805\image_20260326_214243_805.img"
$man = "C:\dev\legacy-doctor\proofs\acquire\image_20260326_214243_805\image_20260326_214243_805.manifest.json"

Require (Test-Path -LiteralPath $img -PathType Leaf) "MISSING_IMAGE" $img
Require (Test-Path -LiteralPath $man -PathType Leaf) "MISSING_MANIFEST" $man

$packOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $PacketizeScript -RepoRoot $RepoRoot -ImagePath $img -ManifestPath $man 2>&1
$packJoined = (@(@($packOut)) -join "`n")
foreach($x in @(@($packOut))){
  [Console]::Out.WriteLine($x)
}
Require ($packJoined -match "LD_PACKETIZE_OK") "PACKETIZE_FAIL" ""

if($packJoined -notmatch 'LD_PACKET_PATH: (.+)'){
  Die "PACKET_PATH_NOT_FOUND" ""
}
$packetRoot = $matches[1].Trim()

$verifyOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $VerifyScript -RepoRoot $RepoRoot -PacketRoot $packetRoot 2>&1
$verifyJoined = (@(@($verifyOut)) -join "`n")
foreach($x in @(@($verifyOut))){
  [Console]::Out.WriteLine($x)
}
Require ($verifyJoined -match "LD_VERIFY_PACKET_OK") "VERIFY_PACKET_FAIL" ""

# Negative tamper
$manifestPath = Join-Path $packetRoot "manifest.json"
Add-Content -LiteralPath $manifestPath -Value "X"

$negOut = $null
$negJoined = ""
try {
  $negOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $VerifyScript -RepoRoot $RepoRoot -PacketRoot $packetRoot 2>&1
  $negJoined = (@(@($negOut)) -join "`n")
}
catch {
  $negJoined = $_.Exception.Message
}

if($negOut){
  foreach($x in @(@($negOut))){
    [Console]::Out.WriteLine($x)
  }
}

Require ($negJoined -match "VERIFY_PACKET_FAIL_PACKET_ID_MISMATCH" -or $negJoined -match "VERIFY_PACKET_FAIL_SHA256SUMS_HASH_MISMATCH") "NEGATIVE_PACKET_TAMPER_NOT_CAUGHT" ""

Write-Host "PASS: packet verify positive" -ForegroundColor Green
Write-Host "PASS: packet tamper negative" -ForegroundColor Green
Write-Host "SELFTEST_LD_VERIFY_PACKET_OK" -ForegroundColor Green
Write-Output "FULL_GREEN"