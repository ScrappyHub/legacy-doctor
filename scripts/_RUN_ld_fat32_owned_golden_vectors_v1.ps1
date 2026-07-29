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

function HexSha256File([string]$Path){
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $fs = [System.IO.File]::OpenRead($Path)
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

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

$RawLib    = Join-Path $RepoRoot "scripts\storage\_lib_ld_rawdisk_v1.ps1"
$LayoutLib = Join-Path $RepoRoot "scripts\storage\_lib_ld_fat32_layout_v1.ps1"
$BootLib   = Join-Path $RepoRoot "scripts\storage\_lib_ld_fat32_boot_v1.ps1"
$Selftest  = Join-Path $RepoRoot "scripts\selftest\_selftest_ld_fat32_owned_writepath_v1.ps1"

foreach($p in @($RawLib,$LayoutLib,$BootLib,$Selftest)){
  Parse-GateFile $p
  Write-Host ("PARSE_OK: " + $p) -ForegroundColor DarkGray
}

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$selfOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $Selftest -RepoRoot $RepoRoot 2>&1

foreach($x in @(@($selfOut))){
  [Console]::Out.WriteLine($x)
}

$selfText = (@(@($selfOut)) -join "`n")
if($selfText -notmatch "FULL_GREEN"){
  Die "SELFTEST_MISSING_FULL_GREEN" $Selftest
}
if($selfText -notmatch "SELFTEST_LD_FAT32_OWNED_WRITEPATH_OK"){
  Die "SELFTEST_MISSING_WRITEPATH_OK" $Selftest
}

. $RawLib
. $LayoutLib
. $BootLib

$VectorDir = Join-Path $RepoRoot "test_vectors\fat32_owned_v1"
EnsureDir $VectorDir

$PlanPath       = Join-Path $VectorDir "plan.json"
$MbrPath        = Join-Path $VectorDir "mbr.bin"
$BootPath       = Join-Path $VectorDir "boot.bin"
$FsInfoPath     = Join-Path $VectorDir "fsinfo.bin"
$BackupBootPath = Join-Path $VectorDir "backup_boot.bin"
$Fat0Path       = Join-Path $VectorDir "fat0.bin"
$Root0Path      = Join-Path $VectorDir "root0.bin"
$SumsPath       = Join-Path $VectorDir "sha256sums.txt"

$plan = LDFAT-NewPlan `
  -DiskSizeBytes 255869321216 `
  -BytesPerSector 512 `
  -DeviceId "win.disk.v1:test:synthetic" `
  -DiskNumber 99 `
  -Label "SDCARD" `
  -ClusterKiB 0

$mbr  = LDFAT-BuildMbrSector $plan
$boot = LDBOOT-BuildBootSector $plan
$fsi  = LDBOOT-BuildFsInfoSector $plan
$bb   = LDBOOT-BuildBackupBootSector $plan
$fat0 = LDBOOT-BuildFatSector0 $plan
$root0 = LDBOOT-BuildRootDirSector0 $plan

[IO.File]::WriteAllBytes($MbrPath,$mbr)
[IO.File]::WriteAllBytes($BootPath,$boot)
[IO.File]::WriteAllBytes($FsInfoPath,$fsi)
[IO.File]::WriteAllBytes($BackupBootPath,$bb)
[IO.File]::WriteAllBytes($Fat0Path,$fat0)
[IO.File]::WriteAllBytes($Root0Path,$root0)

$planJson = ToCanonJson $plan
Write-Utf8NoBomLf -Path $PlanPath -Text $planJson

Require ((Get-Item -LiteralPath $MbrPath).Length -eq 512) "VECTOR_LEN_BAD" "mbr.bin"
Require ((Get-Item -LiteralPath $BootPath).Length -eq 512) "VECTOR_LEN_BAD" "boot.bin"
Require ((Get-Item -LiteralPath $FsInfoPath).Length -eq 512) "VECTOR_LEN_BAD" "fsinfo.bin"
Require ((Get-Item -LiteralPath $BackupBootPath).Length -eq 512) "VECTOR_LEN_BAD" "backup_boot.bin"
Require ((Get-Item -LiteralPath $Fat0Path).Length -eq 512) "VECTOR_LEN_BAD" "fat0.bin"
Require ((Get-Item -LiteralPath $Root0Path).Length -eq 512) "VECTOR_LEN_BAD" "root0.bin"

$sumLines = New-Object System.Collections.Generic.List[string]
[void]$sumLines.Add((HexSha256File $PlanPath) + " *plan.json")
[void]$sumLines.Add((HexSha256File $MbrPath) + " *mbr.bin")
[void]$sumLines.Add((HexSha256File $BootPath) + " *boot.bin")
[void]$sumLines.Add((HexSha256File $FsInfoPath) + " *fsinfo.bin")
[void]$sumLines.Add((HexSha256File $BackupBootPath) + " *backup_boot.bin")
[void]$sumLines.Add((HexSha256File $Fat0Path) + " *fat0.bin")
[void]$sumLines.Add((HexSha256File $Root0Path) + " *root0.bin")

Write-Utf8NoBomLf -Path $SumsPath -Text ($sumLines.ToArray() -join "`n")

Write-Host ("VECTOR_OK: " + $PlanPath) -ForegroundColor Green
Write-Host ("VECTOR_OK: " + $MbrPath) -ForegroundColor Green
Write-Host ("VECTOR_OK: " + $BootPath) -ForegroundColor Green
Write-Host ("VECTOR_OK: " + $FsInfoPath) -ForegroundColor Green
Write-Host ("VECTOR_OK: " + $BackupBootPath) -ForegroundColor Green
Write-Host ("VECTOR_OK: " + $Fat0Path) -ForegroundColor Green
Write-Host ("VECTOR_OK: " + $Root0Path) -ForegroundColor Green
Write-Host ("VECTOR_OK: " + $SumsPath) -ForegroundColor Green

Write-Output "LD_FAT32_OWNED_GOLDEN_VECTORS_OK"