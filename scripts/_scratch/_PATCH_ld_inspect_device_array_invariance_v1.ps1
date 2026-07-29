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
$Target = Join-Path $RepoRoot "scripts\storage\ld_inspect_device_v1.ps1"

$text = Read-Utf8 $Target

$oldCanon = @'
if($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])){
  $arr = @()
  foreach($x in $Value){
    $arr += ,(Canon $x)
  }
  return $arr
}
'@

$newCanon = @'
if($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])){
  $arr = @()
  foreach($x in @($Value)){
    $arr += ,(Canon $x)
  }
  return ,$arr
}
'@

if(-not $text.Contains($oldCanon)){
  Die "PATCH_TARGET_NOT_FOUND" "Canon enumerable block"
}

$text = $text.Replace($oldCanon,$newCanon)

$oldReceipt = @'
$inspectReceipt = LDHEALTH-BuildInspectReceipt -RepoRoot $RepoRoot -Probe $probe
$healthReceipt = LDHEALTH-BuildHealthReceipt -RepoRoot $RepoRoot -Probe $probe
'@

$newReceipt = @'
$inspectReceipt = LDHEALTH-BuildInspectReceipt -RepoRoot $RepoRoot -Probe $probe
$healthReceipt = LDHEALTH-BuildHealthReceipt -RepoRoot $RepoRoot -Probe $probe

# FORCE ARRAY SHAPE BEFORE CANONICALIZATION
$inspectReceipt.partitions = @($inspectReceipt.partitions | ForEach-Object { $_ })
$inspectReceipt.volumes = @($inspectReceipt.volumes | ForEach-Object { $_ })
'@

if(-not $text.Contains($oldReceipt)){
  Die "PATCH_TARGET_NOT_FOUND" "inspect/health receipt block"
}

$text = $text.Replace($oldReceipt,$newReceipt)

Write-Utf8NoBomLf $Target $text
Parse-GateFile $Target

Write-Host ("PATCH_OK TARGET=" + $Target) -ForegroundColor Green