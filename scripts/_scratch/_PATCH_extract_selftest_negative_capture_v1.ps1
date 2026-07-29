param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function Read-Utf8([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "MISSING_FILE" $Path
  }
  return [IO.File]::ReadAllText($Path,[Text.UTF8Encoding]::new($false))
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($Path,$t,[Text.UTF8Encoding]::new($false))
}

function Parse-GateFile([string]$Path){
  $tok = $null
  $err = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tok,[ref]$err)
  if($err -and $err.Count -gt 0){
    $e = $err[0]
    Die "PARSE_GATE_FAIL" ($Path + ":" + $e.Extent.StartLineNumber + ":" + $e.Extent.StartColumnNumber + ": " + $e.Message)
  }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Target = Join-Path $RepoRoot "scripts\selftest\_selftest_ld_extract_image_v1.ps1"
$text = Read-Utf8 $Target

$old = @'
# Negative: missing ranges json for byte_ranges
$negOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ExtractScript -RepoRoot $RepoRoot -ImagePath $imagePath -Mode byte_ranges 2>&1
$negJoined = (@(@($negOut)) -join "`n")
foreach($x in @(@($negOut))){
  [Console]::Out.WriteLine($x)
}
Require ($negJoined -match "RANGES_JSON_REQUIRED") "NEGATIVE_MISSING_RANGES_NOT_CAUGHT" ""
'@

$new = @'
# Negative: missing ranges json for byte_ranges
$negOut = $null
$negJoined = ""

try {
  $negOut = & $PSExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $ExtractScript -RepoRoot $RepoRoot -ImagePath $imagePath -Mode byte_ranges 2>&1
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

Require ($negJoined -match "RANGES_JSON_REQUIRED") "NEGATIVE_MISSING_RANGES_NOT_CAUGHT" ""
'@

if(-not $text.Contains($old)){
  Die "PATCH_TARGET_NOT_FOUND" "extract negative block"
}

$text = $text.Replace($old,$new)

Write-Utf8NoBomLf $Target $text
Parse-GateFile $Target
Write-Host ("PATCH_OK TARGET=" + $Target) -ForegroundColor Green