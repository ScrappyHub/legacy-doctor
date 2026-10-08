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

if($text -notmatch "LD_DEVICE_COPY_MANIFEST_VERIFY_(OK|BLOCKED)"){
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

if($text -match '"invalid_row_count":0'){
  if($text -match '"manifest_row_count":[1-9]' -and $text -notmatch '"ok":true'){
    Die "VALID_MANIFEST_NOT_OK" ""
  }
} else {
  if($text -notmatch '"ok":false'){
    Die "INVALID_MANIFEST_NOT_BLOCKED" ""
  }
  if($text -notmatch 'INVALID_MANIFEST_ROWS'){
    Die "INVALID_MANIFEST_REASON_MISSING" ""
  }
  if($text -notmatch "LD_DEVICE_COPY_MANIFEST_VERIFY_BLOCKED"){
    Die "INVALID_MANIFEST_BLOCK_TOKEN_MISSING" ""
  }
}
if($text -match "LD_DEVICE_COPY_MANIFEST_VERIFY_BLOCKED" -and $text -notmatch 'EMPTY_MANIFEST|MANIFEST_INPUT_UNAVAILABLE|INVALID_MANIFEST_ROWS'){
  Die "MANIFEST_BLOCK_REASON_MISSING" ""
}

Write-Output $text
Write-Output "PASS: copy manifest verifier emitted"
Write-Output "PASS: manifest rows are valid or explicitly blocked with reasons"
Write-Output "PASS: no destination writes and no copy"
Write-Output "PASS: empty or unavailable manifests are blocked"
Write-Output "SELFTEST_LD_STORAGE03_COPY_MANIFEST_VERIFY_OK"
