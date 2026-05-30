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

function EnsureDir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ return }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Utf8NoBom(){
  return (New-Object System.Text.UTF8Encoding($false))
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ EnsureDir $dir }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($Path,$t,(Utf8NoBom))
}

function Append-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ EnsureDir $dir }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::AppendAllText($Path,$t,(Utf8NoBom))
}

function HexSha256Bytes([byte[]]$Bytes){
  if($null -eq $Bytes){ $Bytes = [byte[]]@() }

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($Bytes)
  } finally {
    $sha.Dispose()
  }

  $sb = New-Object System.Text.StringBuilder
  foreach($b in $hash){
    [void]$sb.Append($b.ToString("x2"))
  }
  return $sb.ToString()
}

function HexSha256TextLf([string]$Text){
  if($null -eq $Text){ $Text = "" }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  return (HexSha256Bytes ([Text.Encoding]::UTF8.GetBytes($t)))
}

function HexSha256File([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "MISSING_FILE" $Path
  }

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $fs = [IO.File]::OpenRead($Path)
    try {
      $hash = $sha.ComputeHash($fs)
    } finally {
      $fs.Dispose()
    }
  } finally {
    $sha.Dispose()
  }

  $sb = New-Object System.Text.StringBuilder
  foreach($b in $hash){
    [void]$sb.Append($b.ToString("x2"))
  }
  return $sb.ToString()
}

function Canon([object]$Value){
  if($null -eq $Value){ return $null }

  if(
    $Value -is [string] -or
    $Value -is [int] -or
    $Value -is [long] -or
    $Value -is [double] -or
    $Value -is [decimal] -or
    $Value -is [bool] -or
    $Value -is [byte] -or
    $Value -is [UInt16] -or
    $Value -is [UInt32] -or
    $Value -is [UInt64]
  ){
    return $Value
  }

  if($Value -is [datetime]){
    return $Value.ToUniversalTime().ToString("o")
  }

  if($Value -is [System.Collections.IDictionary]){
    $keys = @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)
    $o = [ordered]@{}
    foreach($k in $keys){
      $o[$k] = Canon $Value[$k]
    }
    return $o
  }

  if($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])){
    $arr = @()
    foreach($x in $Value){
      $arr += ,(Canon $x)
    }
    return $arr
  }

  return ([string]$Value)
}

function ToCanonJson([object]$Value){
  return ((Canon $Value) | ConvertTo-Json -Depth 20 -Compress)
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source

$FilesToParse = @(
  (Join-Path $RepoRoot "scripts\storage\_lib_ld_rawdisk_v1.ps1"),
  (Join-Path $RepoRoot "scripts\storage\_lib_ld_fat32_layout_v1.ps1"),
  (Join-Path $RepoRoot "scripts\storage\_lib_ld_fat32_boot_v1.ps1"),
  (Join-Path $RepoRoot "scripts\storage\_lib_ld_receipts_v1.ps1"),
  (Join-Path $RepoRoot "scripts\storage\ld_verify_fat32_layout_v1.ps1"),
  (Join-Path $RepoRoot "scripts\storage\ld_format_fat32_owned_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_fat32_owned_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_fat32_owned_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_fat32_boot_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_fat32_boot_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_fat32_owned_writepath_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_fat32_owned_writepath_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_ld_fat32_owned_golden_vectors_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_fat32_owned_vectors_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_fat32_owned_vectors_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_fat32_owned_imagefile_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_fat32_owned_imagefile_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_fat32_owned_verify_imagefile_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_fat32_owned_verify_imagefile_v1.ps1"),
  (Join-Path $RepoRoot "scripts\selftest\_selftest_ld_fat32_imagefile_receipt_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_fat32_imagefile_receipt_v1.ps1")
)

foreach($p in $FilesToParse){
  Parse-GateFile $p
  Write-Output ("PARSE_OK: " + $p)
}

$RequiredArtifacts = @(
  (Join-Path $RepoRoot "schemas\ld.fat32.imagefile.receipt.v1.json"),
  (Join-Path $RepoRoot "docs\LEGACY_DOCTOR_FAT32_OWNED_SPEC_v1.md"),
  (Join-Path $RepoRoot "docs\WBS\LD_STORAGE_02A_PROGRESS_LEDGER_v1.md"),
  (Join-Path $RepoRoot "test_vectors\fat32_owned_v1\plan.json"),
  (Join-Path $RepoRoot "test_vectors\fat32_owned_v1\mbr.bin"),
  (Join-Path $RepoRoot "test_vectors\fat32_owned_v1\boot.bin"),
  (Join-Path $RepoRoot "test_vectors\fat32_owned_v1\fsinfo.bin"),
  (Join-Path $RepoRoot "test_vectors\fat32_owned_v1\backup_boot.bin"),
  (Join-Path $RepoRoot "test_vectors\fat32_owned_v1\fat0.bin"),
  (Join-Path $RepoRoot "test_vectors\fat32_owned_v1\root0.bin"),
  (Join-Path $RepoRoot "test_vectors\fat32_owned_v1\sha256sums.txt")
)

foreach($p in $RequiredArtifacts){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
    Die "REQUIRED_ARTIFACT_MISSING" $p
  }
  Write-Output ("ARTIFACT_OK: " + $p)
}

$RunRoot = Join-Path $RepoRoot "proofs\receipts\legacy_doctor_tier0_full_green"
EnsureDir $RunRoot

$RunId = "ld_tier0_full_green_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")
$ThisRunDir = Join-Path $RunRoot $RunId
EnsureDir $ThisRunDir

$StdoutPath = Join-Path $ThisRunDir "stdout.txt"
$StderrPath = Join-Path $ThisRunDir "stderr.txt"
$SummaryPath = Join-Path $ThisRunDir "summary.json"
$SumsPath = Join-Path $ThisRunDir "sha256sums.txt"
$LedgerPath = Join-Path $RepoRoot "proofs\receipts\legacy_doctor_tier0_full_green.ndjson"

$Runners = @(
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_fat32_owned_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_fat32_boot_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_fat32_owned_writepath_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_ld_fat32_owned_golden_vectors_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_fat32_owned_vectors_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_fat32_owned_imagefile_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_fat32_owned_verify_imagefile_v1.ps1"),
  (Join-Path $RepoRoot "scripts\_RUN_legacy_doctor_fat32_imagefile_receipt_v1.ps1")
)

$AllOutput = @()
$ResultRows = @()

foreach($runner in $Runners){
  $name = Split-Path -Leaf $runner
  $AllOutput += ("RUNNER_START: " + $runner)

  $rawOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $runner -RepoRoot $RepoRoot 2>&1
  $exitCode = $LASTEXITCODE

  $lines = @()
  if($rawOut -is [System.Array]){
    foreach($x in $rawOut){
      $lines += [string]$x
    }
  } elseif($null -ne $rawOut){
    $lines += [string]$rawOut
  }

  foreach($line in $lines){
    $AllOutput += $line
  }

  $joined = ($lines -join "`n")

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

  $ResultRows += [pscustomobject]@{
    runner = $name
    ok = $true
  }
}

Write-Utf8NoBomLf $StdoutPath ($AllOutput -join "`n")
Write-Utf8NoBomLf $StderrPath ""

$Summary = [ordered]@{
  schema = "legacy_doctor.tier0.full_green.summary.v1"
  run_id = $RunId
  utc = [DateTime]::UtcNow.ToString("o")
  repo_root = $RepoRoot
  runners = @($ResultRows)
  ok = $true
}

$SummaryJson = ToCanonJson $Summary
Write-Utf8NoBomLf $SummaryPath $SummaryJson

$SumLines = @()
foreach($p in @($StdoutPath,$StderrPath,$SummaryPath)){
  $SumLines += ((HexSha256File $p) + " *" + (Split-Path -Leaf $p))
}
Write-Utf8NoBomLf $SumsPath ($SumLines -join "`n")

$LedgerObj = [ordered]@{
  schema = "legacy_doctor.tier0.full_green.receipt.v1"
  run_id = $RunId
  utc = [DateTime]::UtcNow.ToString("o")
  repo_root = $RepoRoot
  run_dir = $ThisRunDir
  stdout_sha256 = (HexSha256File $StdoutPath)
  stderr_sha256 = (HexSha256File $StderrPath)
  summary_sha256 = (HexSha256File $SummaryPath)
  sha256sums_sha256 = (HexSha256File $SumsPath)
  ok = $true
}

$LedgerJson = ToCanonJson $LedgerObj
$LedgerHash = HexSha256TextLf $LedgerJson

$LedgerFinal = [ordered]@{
  schema = $LedgerObj.schema
  run_id = $LedgerObj.run_id
  utc = $LedgerObj.utc
  repo_root = $LedgerObj.repo_root
  run_dir = $LedgerObj.run_dir
  stdout_sha256 = $LedgerObj.stdout_sha256
  stderr_sha256 = $LedgerObj.stderr_sha256
  summary_sha256 = $LedgerObj.summary_sha256
  sha256sums_sha256 = $LedgerObj.sha256sums_sha256
  ok = $LedgerObj.ok
  receipt_hash = $LedgerHash
}

Append-Utf8NoBomLf $LedgerPath (ToCanonJson $LedgerFinal)

Write-Output ("RUN_DIR: " + $ThisRunDir)
Write-Output ("LEDGER_PATH: " + $LedgerPath)
Write-Output "LEGACY_DOCTOR_TIER0_ALL_GREEN"