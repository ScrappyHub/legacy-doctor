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
$planJsonActual = ToCanonJson $plan
$planJsonExpected = Read-Utf8NoBom $PlanPath
Require ($planJsonActual -eq $planJsonExpected) "PLAN_JSON_MISMATCH" "generated plan.json differs from frozen vector"
Write-Host "PASS: plan.json exact match" -ForegroundColor Green
'@

$new = @'
$planJsonActual = ToCanonJson $plan
$planJsonExpected = Read-Utf8NoBom $PlanPath
$planJsonExpected = ($planJsonExpected -replace "`r`n","`n") -replace "`r","`n"
if($planJsonExpected.EndsWith("`n")){
  $planJsonExpected = $planJsonExpected.Substring(0,$planJsonExpected.Length - 1)
}
Require ($planJsonActual -eq $planJsonExpected) "PLAN_JSON_MISMATCH" "generated plan.json differs from frozen vector"
Write-Host "PASS: plan.json exact match" -ForegroundColor Green
'@

if($text.IndexOf($old,[System.StringComparison]::Ordinal) -lt 0){
  Die "PATCH_TARGET_BLOCK_NOT_FOUND" "plan json compare block"
}

$text2 = $text.Replace($old,$new)

Write-Utf8NoBomLf -Path $Target -Text $text2
Parse-GateFile $Target
Write-Output ("PATCH_OK TARGET=" + $Target)