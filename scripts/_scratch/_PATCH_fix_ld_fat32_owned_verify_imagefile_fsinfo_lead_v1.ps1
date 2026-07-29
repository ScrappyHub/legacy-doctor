param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function Utf8NoBom(){
  return (New-Object System.Text.UTF8Encoding($false))
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
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
$Target = Join-Path $RepoRoot "scripts\selftest\_selftest_ld_fat32_owned_verify_imagefile_v1.ps1"

if(-not (Test-Path -LiteralPath $Target -PathType Leaf)){
  Die "MISSING_TARGET" $Target
}

$text = [IO.File]::ReadAllText($Target,(Utf8NoBom))
$text = ($text -replace "`r`n","`n") -replace "`r","`n"

$old = 'Require ((LD-GetU32LE -Buffer $fsi -Offset 0) -eq [UInt32]4161526986) "VERIFY_FAIL_FSINFO_LEAD" ("actual=" + (LD-GetU32LE -Buffer $fsi -Offset 0))'
$new = 'Require ((LD-GetU32LE -Buffer $fsi -Offset 0) -eq [UInt32]1096897106) "VERIFY_FAIL_FSINFO_LEAD" ("actual=" + (LD-GetU32LE -Buffer $fsi -Offset 0))'

if($text.IndexOf($old,[System.StringComparison]::Ordinal) -lt 0){
  Die "PATCH_TARGET_BLOCK_NOT_FOUND" $old
}

$text2 = $text.Replace($old,$new)

Write-Utf8NoBomLf -Path $Target -Text $text2
Parse-GateFile $Target
Write-Output ("PATCH_OK TARGET=" + $Target)