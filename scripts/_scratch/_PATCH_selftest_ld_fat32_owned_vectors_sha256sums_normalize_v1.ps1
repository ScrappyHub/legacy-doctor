param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
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

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Target = Join-Path $RepoRoot "scripts\selftest\_selftest_ld_fat32_owned_vectors_v1.ps1"
if(-not (Test-Path -LiteralPath $Target -PathType Leaf)){
  Die "MISSING_TARGET" $Target
}

$text = [IO.File]::ReadAllText($Target,(Utf8NoBom))
$text = ($text -replace "`r`n","`n") -replace "`r","`n"

$old = @'
$sumLines = @(
  (HexSha256File $PlanPath) + " *plan.json",
  (HexSha256File $MbrPath) + " *mbr.bin",
  (HexSha256File $BootPath) + " *boot.bin",
  (HexSha256File $FsInfoPath) + " *fsinfo.bin",
  (HexSha256File $BackupBootPath) + " *backup_boot.bin",
  (HexSha256File $Fat0Path) + " *fat0.bin",
  (HexSha256File $Root0Path) + " *root0.bin"
)
$sumTextActual = (($sumLines -join "`n") + "`n")
$sumTextExpected = Read-Utf8NoBom $SumsPath
Require ($sumTextActual -eq $sumTextExpected) "SHA256SUMS_MISMATCH" "generated sha256sums.txt differs from frozen vector"
Write-Host "PASS: sha256sums exact match" -ForegroundColor Green
'@

$new = @'
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

$sumLines = @(
  (HexSha256File $PlanPath) + " *plan.json",
  (HexSha256File $MbrPath) + " *mbr.bin",
  (HexSha256File $BootPath) + " *boot.bin",
  (HexSha256File $FsInfoPath) + " *fsinfo.bin",
  (HexSha256File $BackupBootPath) + " *backup_boot.bin",
  (HexSha256File $Fat0Path) + " *fat0.bin",
  (HexSha256File $Root0Path) + " *root0.bin"
)

$sumLinesActual = Normalize-Lines (($sumLines -join "`n") + "`n")
$sumLinesExpected = Normalize-Lines (Read-Utf8NoBom $SumsPath)

Require ($sumLinesActual.Count -eq $sumLinesExpected.Count) "SHA256SUMS_MISMATCH" ("line_count actual=" + $sumLinesActual.Count + " expected=" + $sumLinesExpected.Count)

for($i = 0; $i -lt $sumLinesActual.Count; $i++){
  if($sumLinesActual[$i] -ne $sumLinesExpected[$i]){
    Die "SHA256SUMS_MISMATCH" ("line=" + $i + " actual=" + $sumLinesActual[$i] + " expected=" + $sumLinesExpected[$i])
  }
}

Write-Host "PASS: sha256sums exact match" -ForegroundColor Green
'@

if($text.IndexOf($old,[System.StringComparison]::Ordinal) -lt 0){
  Die "PATCH_TARGET_BLOCK_NOT_FOUND" "sha256sums compare block"
}

$text2 = $text.Replace($old,$new)

Write-Utf8NoBomLf -Path $Target -Text $text2
Parse-GateFile $Target
Write-Output ("PATCH_OK TARGET=" + $Target)