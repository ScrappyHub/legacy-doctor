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

function Utf8NoBom(){
  return (New-Object System.Text.UTF8Encoding($false))
}

function Read-Utf8NoBom([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "MISSING_FILE" $Path
  }
  return [IO.File]::ReadAllText($Path,(Utf8NoBom))
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
  return ((Canon $Value) | ConvertTo-Json -Depth 100 -Compress)
}

function HexSha256TextLf([string]$Text){
  if($null -eq $Text){ $Text = "" }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  return (HexSha256Bytes ([Text.Encoding]::UTF8.GetBytes($t)))
}

function Compare-BytesExact([string]$Name,[byte[]]$Actual,[byte[]]$Expected){
  Require ($null -ne $Actual) "NULL_ACTUAL" $Name
  Require ($null -ne $Expected) "NULL_EXPECTED" $Name
  Require ($Actual.Length -eq $Expected.Length) "VECTOR_LEN_MISMATCH" ($Name + ": actual=" + $Actual.Length + " expected=" + $Expected.Length)

  for($i = 0; $i -lt $Actual.Length; $i++){
    if($Actual[$i] -ne $Expected[$i]){
      Die "VECTOR_BYTE_MISMATCH" ($Name + ": offset=" + $i + " actual=" + $Actual[$i] + " expected=" + $Expected[$i])
    }
  }
}

function Normalize-Lines([string]$Text){
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  $parts = @($t -split "`n")
  $lines = New-Object System.Collections.Generic.List[string]
  foreach($line in $parts){
    if(-not [string]::IsNullOrWhiteSpace($line)){
      [void]$lines.Add($line.Trim())
    }
  }
  return @($lines.ToArray())
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$RawLib        = Join-Path $RepoRoot "scripts\storage\_lib_ld_rawdisk_v1.ps1"
$LayoutLib     = Join-Path $RepoRoot "scripts\storage\_lib_ld_fat32_layout_v1.ps1"
$BootLib       = Join-Path $RepoRoot "scripts\storage\_lib_ld_fat32_boot_v1.ps1"
$WriteSelftest = Join-Path $RepoRoot "scripts\selftest\_selftest_ld_fat32_owned_writepath_v1.ps1"

$VectorDir      = Join-Path $RepoRoot "test_vectors\fat32_owned_v1"
$PlanPath       = Join-Path $VectorDir "plan.json"
$MbrPath        = Join-Path $VectorDir "mbr.bin"
$BootPath       = Join-Path $VectorDir "boot.bin"
$FsInfoPath     = Join-Path $VectorDir "fsinfo.bin"
$BackupBootPath = Join-Path $VectorDir "backup_boot.bin"
$Fat0Path       = Join-Path $VectorDir "fat0.bin"
$Root0Path      = Join-Path $VectorDir "root0.bin"
$SumsPath       = Join-Path $VectorDir "sha256sums.txt"

foreach($p in @($RawLib,$LayoutLib,$BootLib,$WriteSelftest)){
  Parse-GateFile $p
  Write-Host ("PARSE_OK: " + $p) -ForegroundColor DarkGray
}

foreach($p in @($PlanPath,$MbrPath,$BootPath,$FsInfoPath,$BackupBootPath,$Fat0Path,$Root0Path,$SumsPath)){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
    Die "MISSING_VECTOR" $p
  }
}

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$writeSelftestOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $WriteSelftest -RepoRoot $RepoRoot 2>&1

foreach($x in @(@($writeSelftestOut))){
  [Console]::Out.WriteLine($x)
}

$writeSelftestText = (@(@($writeSelftestOut)) -join "`n")
if($writeSelftestText -notmatch "FULL_GREEN"){
  Die "WRITEPATH_SELFTEST_MISSING_FULL_GREEN" $WriteSelftest
}
if($writeSelftestText -notmatch "SELFTEST_LD_FAT32_OWNED_WRITEPATH_OK"){
  Die "WRITEPATH_SELFTEST_MISSING_OK" $WriteSelftest
}

. $RawLib
. $LayoutLib
. $BootLib

$plan = LDFAT-NewPlan `
  -DiskSizeBytes 255869321216 `
  -BytesPerSector 512 `
  -DeviceId "win.disk.v1:test:synthetic" `
  -DiskNumber 99 `
  -Label "SDCARD" `
  -ClusterKiB 0

$mbr   = LDFAT-BuildMbrSector $plan
$boot  = LDBOOT-BuildBootSector $plan
$fsi   = LDBOOT-BuildFsInfoSector $plan
$bb    = LDBOOT-BuildBackupBootSector $plan
$fat0  = LDBOOT-BuildFatSector0 $plan
$root0 = LDBOOT-BuildRootDirSector0 $plan

$planJsonActual = ToCanonJson $plan
$planHashActual = HexSha256TextLf $planJsonActual
$planHashExpected = HexSha256File $PlanPath
Require ($planHashActual -eq $planHashExpected) "PLAN_JSON_MISMATCH" ("generated plan.json hash differs from frozen vector: actual=" + $planHashActual + " expected=" + $planHashExpected)
Write-Host "PASS: plan.json exact match" -ForegroundColor Green

$mbrExpected   = [IO.File]::ReadAllBytes($MbrPath)
$bootExpected  = [IO.File]::ReadAllBytes($BootPath)
$fsiExpected   = [IO.File]::ReadAllBytes($FsInfoPath)
$bbExpected    = [IO.File]::ReadAllBytes($BackupBootPath)
$fat0Expected  = [IO.File]::ReadAllBytes($Fat0Path)
$root0Expected = [IO.File]::ReadAllBytes($Root0Path)

Compare-BytesExact -Name "mbr.bin" -Actual $mbr -Expected $mbrExpected
Write-Host "PASS: mbr.bin exact match" -ForegroundColor Green

Compare-BytesExact -Name "boot.bin" -Actual $boot -Expected $bootExpected
Write-Host "PASS: boot.bin exact match" -ForegroundColor Green

Compare-BytesExact -Name "fsinfo.bin" -Actual $fsi -Expected $fsiExpected
Write-Host "PASS: fsinfo.bin exact match" -ForegroundColor Green

Compare-BytesExact -Name "backup_boot.bin" -Actual $bb -Expected $bbExpected
Write-Host "PASS: backup_boot.bin exact match" -ForegroundColor Green

Compare-BytesExact -Name "fat0.bin" -Actual $fat0 -Expected $fat0Expected
Write-Host "PASS: fat0.bin exact match" -ForegroundColor Green

Compare-BytesExact -Name "root0.bin" -Actual $root0 -Expected $root0Expected
Write-Host "PASS: root0.bin exact match" -ForegroundColor Green

$sumLinesActual = Normalize-Lines @"
$(HexSha256File $PlanPath) *plan.json
$(HexSha256File $MbrPath) *mbr.bin
$(HexSha256File $BootPath) *boot.bin
$(HexSha256File $FsInfoPath) *fsinfo.bin
$(HexSha256File $BackupBootPath) *backup_boot.bin
$(HexSha256File $Fat0Path) *fat0.bin
$(HexSha256File $Root0Path) *root0.bin
"@

$sumLinesExpected = Normalize-Lines (Read-Utf8NoBom $SumsPath)

Require ($sumLinesActual.Count -eq $sumLinesExpected.Count) "SHA256SUMS_MISMATCH" ("line_count actual=" + $sumLinesActual.Count + " expected=" + $sumLinesExpected.Count)

for($i = 0; $i -lt $sumLinesActual.Count; $i++){
  if($sumLinesActual[$i] -ne $sumLinesExpected[$i]){
    Die "SHA256SUMS_MISMATCH" ("line=" + $i + " actual=" + $sumLinesActual[$i] + " expected=" + $sumLinesExpected[$i])
  }
}

Write-Host "PASS: sha256sums exact match" -ForegroundColor Green

$liveHashes = [ordered]@{
  plan_hash = $planHashActual
  mbr = (HexSha256Bytes $mbr)
  boot = (HexSha256Bytes $boot)
  fsinfo = (HexSha256Bytes $fsi)
  backup_boot = (HexSha256Bytes $bb)
  fat0 = (HexSha256Bytes $fat0)
  root0 = (HexSha256Bytes $root0)
}
$liveHashesJson = ($liveHashes | ConvertTo-Json -Depth 20 -Compress)
Write-Host ("VECTOR_COMPARE_HASHES: " + $liveHashesJson) -ForegroundColor Cyan

Write-Host "SELFTEST_LD_FAT32_OWNED_VECTORS_OK" -ForegroundColor Green
Write-Output "FULL_GREEN"
