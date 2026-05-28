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
$Target = Join-Path $RepoRoot "scripts\storage\ld_verify_image_v1.ps1"

$text = Read-Utf8 $Target

$changed = $false

$oldIf = 'if(Has-Prop $manifest "byte_ranges" -and $null -ne $manifest.byte_ranges){'
$newIf = @'
$byteRanges = $null
if(Has-Prop $manifest "byte_ranges"){
  $byteRanges = $manifest.PSObject.Properties["byte_ranges"].Value
}

if($null -ne $byteRanges){
'@

if($text.Contains($oldIf)){
  $text = $text.Replace($oldIf,$newIf)
  $changed = $true
}

$oldForeach = 'foreach($r in @($manifest.byte_ranges)){'
$newForeach = 'foreach($r in @($byteRanges)){'

if($text.Contains($oldForeach)){
  $text = $text.Replace($oldForeach,$newForeach)
  $changed = $true
}

# Safety net: fail if any direct manifest.byte_ranges access remains.
if($text -match '\$manifest\.byte_ranges'){
  Die "DIRECT_BYTERANGES_ACCESS_REMAINS" "ld_verify_image_v1.ps1"
}

if(-not $changed){
  Die "PATCH_TARGET_NOT_FOUND" "byte_ranges strict block"
}

Write-Utf8NoBomLf -Path $Target -Text $text
Parse-GateFile -Path $Target

Write-Host ("PATCH_OK TARGET=" + $Target) -ForegroundColor Green