param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Probe = Join-Path $RepoRoot "scripts\storage\ld_copy_manifest_verify_v1.ps1"

$out = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Probe -RepoRoot $RepoRoot -MaxFilesPerSource 20 -MaxDirsPerSource 10 -MaxSamplesPerSource 5
if($LASTEXITCODE -ne 0){ Die "COPY_MANIFEST_VERIFY_EXIT_NONZERO" ([string]$LASTEXITCODE) }

$text = ($out -join "`n")

if($text -notmatch "LD_DEVICE_COPY_MANIFEST_VERIFY_OK"){
  Die "COPY_MANIFEST_VERIFY_TOKEN_MISSING" ""
}

if($text -notmatch '"destructive":false'){
  Die "DESTRUCTIVE_FALSE_MISSING" ""
}

if($text -notmatch '"performs_copy":false'){
  Die "PERFORMS_COPY_FALSE_MISSING" ""
}

if($text -notmatch '"writes_destination":false'){
  Die "WRITES_DESTINATION_FALSE_MISSING" ""
}

if($text -notmatch '"hashes_file_contents":false'){
  Die "HASHES_FILE_CONTENTS_FALSE_MISSING" ""
}

if($text -notmatch '"invalid_row_count":0'){
  Die "INVALID_ROWS_PRESENT" ""
}

Write-Output $text
Write-Output "PASS: copy manifest verifier emitted"
Write-Output "PASS: all manifest rows structurally valid"
Write-Output "PASS: no destination writes and no copy"
Write-Output "SELFTEST_LD_STORAGE03_COPY_MANIFEST_VERIFY_OK"
