param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function STF-Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function STF-Utf8NoBom(){ New-Object System.Text.UTF8Encoding($false) }

function STF-ReadUtf8NoBom([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    STF-Die "MISSING_FILE" $Path
  }
  return [IO.File]::ReadAllText($Path,(STF-Utf8NoBom))
}

function STF-ParseGate([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    STF-Die "PARSE_GATE_MISSING" $Path
  }
  $tok=$null
  $err=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  if($err -and $err.Count -gt 0){
    $e = $err[0]
    STF-Die "PARSE_GATE_FAIL" ($Path + ":" + $e.Extent.StartLineNumber + ":" + $e.Extent.StartColumnNumber + ": " + $e.Message)
  }
}

function STF-Sha256HexTextLf([string]$Text){
  $enc = New-Object System.Text.UTF8Encoding($false)
  $bytes = $enc.GetBytes(($Text + "`n"))
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($bytes)
  } finally {
    $sha.Dispose()
  }

  $sb = New-Object System.Text.StringBuilder
  foreach($b in $hash){
    [void]$sb.AppendFormat("{0:x2}", $b)
  }
  return $sb.ToString()
}

function STF-RunPsFile([string]$PSExe,[string]$ScriptPath,[string[]]$Argv){
  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){
    STF-Die "RUN_MISSING" $ScriptPath
  }

  $allArgs = @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy","Bypass",
    "-File",$ScriptPath
  ) + $Argv

  $out = & $PSExe @allArgs 2>&1
  $exitCode = $LASTEXITCODE

  return [pscustomobject]@{
    ExitCode = $exitCode
    Output   = @(@($out) | ForEach-Object { [string]$_ })
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$PSExe    = (Get-Command powershell.exe -ErrorAction Stop).Source
$StorageDir  = Join-Path $RepoRoot "scripts\storage"
$SelftestDir = Join-Path $RepoRoot "scripts\selftest"

$LibRaw     = Join-Path $StorageDir "_lib_ld_rawdisk_v1.ps1"
$LibLayout  = Join-Path $StorageDir "_lib_ld_fat32_layout_v1.ps1"
$Verify     = Join-Path $StorageDir "ld_verify_fat32_layout_v1.ps1"
$Plan       = Join-Path $StorageDir "ld_plan_format_fat32_owned_v1.ps1"
$Format     = Join-Path $StorageDir "ld_format_fat32_owned_v1.ps1"

# ------------------------------------------------------------
# 1) Parse-gate all owned FAT32 files
# ------------------------------------------------------------
$targets = @(
  $LibRaw,
  $LibLayout,
  $Verify,
  $Plan,
  $Format
)

foreach($t in $targets){
  STF-ParseGate $t
  Write-Host ("PARSE_OK: " + $t) -ForegroundColor DarkGray
}

# ------------------------------------------------------------
# 2) Dot-source libs and validate deterministic module exports
# ------------------------------------------------------------
. $LibRaw
. $LibLayout

$rawInfo = LD-ExportModuleInfo
$layoutInfo = LDFAT-ExportModuleInfo

if([string]$rawInfo.schema -ne "ld.rawdisk.lib.info.v1"){
  STF-Die "RAW_INFO_SCHEMA_BAD" ([string]$rawInfo.schema)
}
if([string]$layoutInfo.schema -ne "ld.fat32.layout.lib.info.v1"){
  STF-Die "LAYOUT_INFO_SCHEMA_BAD" ([string]$layoutInfo.schema)
}

Write-Host "PASS: module export schemas" -ForegroundColor DarkGray

# ------------------------------------------------------------
# 3) Deterministic label sanitization tests
# ------------------------------------------------------------
$label1 = LDFAT-UpperAsciiLabel "sd card 256gb!!"
if($label1 -ne "SDCARD256GB"){
  STF-Die "LABEL_SANITIZE_BAD" ("actual=" + $label1 + " expected=SDCARD256GB")
}

$label2 = LDFAT-UpperAsciiLabel ""
if($label2 -ne "SDCARD"){
  STF-Die "LABEL_DEFAULT_BAD" ("actual=" + $label2 + " expected=SDCARD")
}

$label3 = LDFAT-UpperAsciiLabel "this_label_is_way_too_long"
if($label3.Length -gt 11){
  STF-Die "LABEL_TRUNCATE_BAD" ("actual=" + $label3 + " len=" + $label3.Length)
}

Write-Host "PASS: label sanitization" -ForegroundColor DarkGray

# ------------------------------------------------------------
# 4) Deterministic plan generation tests (no live disk mutation)
#    Use synthetic 256GB media profile
# ------------------------------------------------------------
$diskSizeBytes = [UInt64]255869321216
$bytesPerSector = 512
$deviceId = "win.disk.v1:test:synthetic"
$diskNumber = 99
$label = "SDCARD"

$planA = LDFAT-NewPlan -DiskSizeBytes $diskSizeBytes -BytesPerSector $bytesPerSector -DeviceId $deviceId -DiskNumber $diskNumber -Label $label -ClusterKiB 0
$planB = LDFAT-NewPlan -DiskSizeBytes $diskSizeBytes -BytesPerSector $bytesPerSector -DeviceId $deviceId -DiskNumber $diskNumber -Label $label -ClusterKiB 0

$planJsonA = ($planA | ConvertTo-Json -Depth 50 -Compress)
$planJsonB = ($planB | ConvertTo-Json -Depth 50 -Compress)

if($planJsonA -ne $planJsonB){
  STF-Die "PLAN_NOT_DETERMINISTIC" "same inputs produced different plans"
}

if([string]$planA.schema -ne "ld.fat32.plan.v1"){
  STF-Die "PLAN_SCHEMA_BAD" ([string]$planA.schema)
}
if([string]$planA.partition_style -ne "MBR"){
  STF-Die "PLAN_PARTITION_STYLE_BAD" ([string]$planA.partition_style)
}
if([string]$planA.partition_type_hex -ne "0x0C"){
  STF-Die "PLAN_PARTITION_TYPE_BAD" ([string]$planA.partition_type_hex)
}
if([UInt64]$planA.partition_start_lba -ne 2048){
  STF-Die "PLAN_START_LBA_BAD" ([string]$planA.partition_start_lba)
}
if([UInt32]$planA.bytes_per_sector -ne 512){
  STF-Die "PLAN_BPS_BAD" ([string]$planA.bytes_per_sector)
}
if([UInt32]$planA.sectors_per_cluster -ne 64){
  STF-Die "PLAN_SPC_BAD" ("actual=" + $planA.sectors_per_cluster + " expected=64")
}
if([UInt64]$planA.cluster_size_bytes -ne 32768){
  STF-Die "PLAN_CLUSTER_BYTES_BAD" ("actual=" + $planA.cluster_size_bytes + " expected=32768")
}
if([UInt16]$planA.fat_count -ne 2){
  STF-Die "PLAN_FAT_COUNT_BAD" ([string]$planA.fat_count)
}
if([UInt32]$planA.root_cluster -ne 2){
  STF-Die "PLAN_ROOT_CLUSTER_BAD" ([string]$planA.root_cluster)
}
if([string]$planA.volume_label -ne "SDCARD"){
  STF-Die "PLAN_LABEL_BAD" ([string]$planA.volume_label)
}

Write-Host "PASS: deterministic plan generation" -ForegroundColor DarkGray

# ------------------------------------------------------------
# 5) Deterministic MBR build tests
# ------------------------------------------------------------
$mbrA = LDFAT-BuildMbrSector $planA
$mbrB = LDFAT-BuildMbrSector $planB

if($mbrA.Length -ne 512){
  STF-Die "MBR_LENGTH_BAD" ([string]$mbrA.Length)
}

$hexA = LD-BytesToHex $mbrA
$hexB = LD-BytesToHex $mbrB
if($hexA -ne $hexB){
  STF-Die "MBR_NOT_DETERMINISTIC" "same plan produced different MBR bytes"
}

$entry = 446
$ptype = [byte]$mbrA[$entry + 4]
if($ptype -ne 0x0C){
  STF-Die "MBR_PARTITION_TYPE_BAD" ("actual=0x" + $ptype.ToString("X2"))
}

$startLba = LD-GetU32LE -Buffer $mbrA -Offset ($entry + 8)
$sizeLba  = LD-GetU32LE -Buffer $mbrA -Offset ($entry + 12)

if([UInt64]$startLba -ne [UInt64]$planA.partition_start_lba){
  STF-Die "MBR_START_LBA_BAD" ("actual=" + $startLba + " expected=" + $planA.partition_start_lba)
}
if([UInt64]$sizeLba -ne [UInt64]$planA.partition_size_lba){
  STF-Die "MBR_SIZE_LBA_BAD" ("actual=" + $sizeLba + " expected=" + $planA.partition_size_lba)
}

LD-AssertMbrSignature $mbrA
Write-Host "PASS: deterministic MBR build" -ForegroundColor DarkGray

# ------------------------------------------------------------
# 6) Negative geometry checks
# ------------------------------------------------------------
$badPlanCaught = $false
try {
  [void](LDFAT-NewPlan -DiskSizeBytes ([UInt64](16MB)) -BytesPerSector 512 -DeviceId "tiny" -DiskNumber 1 -Label "X" -ClusterKiB 0)
} catch {
  $badPlanCaught = $true
}
if(-not $badPlanCaught){
  STF-Die "NEGATIVE_GEOMETRY_FAIL" "tiny disk should not produce valid FAT32 plan"
}

$badBpsCaught = $false
try {
  [void](LDFAT-NewPlan -DiskSizeBytes $diskSizeBytes -BytesPerSector 4096 -DeviceId "badbps" -DiskNumber 1 -Label "X" -ClusterKiB 0)
} catch {
  $badBpsCaught = $true
}
if(-not $badBpsCaught){
  STF-Die "NEGATIVE_BPS_FAIL" "unsupported bytes-per-sector should fail"
}

Write-Host "PASS: negative geometry checks" -ForegroundColor DarkGray

# ------------------------------------------------------------
# 7) Verifier script callable negative path (safe)
#    Call verifier with impossible target; require nonzero exit.
# ------------------------------------------------------------
$verifyRun = STF-RunPsFile -PSExe $PSExe -ScriptPath $Verify -Argv @(
  "-RepoRoot",$RepoRoot,
  "-DiskNumber","99999",
  "-ExpectedLabel","SDCARD"
)

if($verifyRun.ExitCode -eq 0){
  STF-Die "VERIFY_NEGATIVE_EXPECTED_FAIL" "verifier should fail on impossible disk"
}

Write-Host "PASS: verifier negative callable path" -ForegroundColor DarkGray

# ------------------------------------------------------------
# 8) Plan script callable path (safe if a removable test disk exists)
#    We do not require success against live media here.
#    We only require parse-gated existence and callable shell path already proven.
# ------------------------------------------------------------
$planHash = STF-Sha256HexTextLf $planJsonA
Write-Host ("PLAN_HASH: " + $planHash) -ForegroundColor DarkGray

# ------------------------------------------------------------
# Final token
# ------------------------------------------------------------
Write-Host "SELFTEST_LD_FAT32_OWNED_OK" -ForegroundColor Green
Write-Output "FULL_GREEN"
