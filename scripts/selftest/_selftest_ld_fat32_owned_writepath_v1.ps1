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

$RawLib      = Join-Path $RepoRoot "scripts\storage\_lib_ld_rawdisk_v1.ps1"
$LayoutLib   = Join-Path $RepoRoot "scripts\storage\_lib_ld_fat32_layout_v1.ps1"
$BootLib     = Join-Path $RepoRoot "scripts\storage\_lib_ld_fat32_boot_v1.ps1"
$VerifyPs1   = Join-Path $RepoRoot "scripts\storage\ld_verify_fat32_layout_v1.ps1"
$FormatPs1   = Join-Path $RepoRoot "scripts\storage\ld_format_fat32_owned_v1.ps1"
$SelftestPs1 = Join-Path $RepoRoot "scripts\selftest\_selftest_ld_fat32_owned_writepath_v1.ps1"

foreach($p in @($RawLib,$LayoutLib,$BootLib,$VerifyPs1,$FormatPs1,$SelftestPs1)){
  Parse-GateFile $p
  Write-Host ("PARSE_OK: " + $p) -ForegroundColor DarkGray
}

$PSExe = (Get-Command powershell.exe -ErrorAction Stop).Source
$out = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $SelftestPs1 -RepoRoot $RepoRoot 2>&1

foreach($x in @(@($out))){
  [Console]::Out.WriteLine($x)
}

$text = (@(@($out)) -join "`n")
if($text -notmatch "FULL_GREEN"){
  Die "SELFTEST_MISSING_FULL_GREEN" $SelftestPs1
}
if($text -notmatch "SELFTEST_LD_FAT32_OWNED_WRITEPATH_OK"){
  Die "SELFTEST_MISSING_WRITEPATH_OK" $SelftestPs1
}

Write-Output "LEGACY_DOCTOR_FAT32_OWNED_WRITEPATH_ALL_GREEN"
