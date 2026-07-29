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

function Read-Utf8NoBom([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "MISSING_FILE" $Path
  }
  return [IO.File]::ReadAllText($Path,(Utf8NoBom))
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

$txt = Read-Utf8NoBom $Target
$txt = ($txt -replace "`r`n","`n") -replace "`r","`n"

$oldBlock = @'
$planJsonActual = ($plan | ConvertTo-Json -Depth 100 -Compress)
$planJsonExpected = Read-Utf8NoBom $PlanPath

Require ($planJsonActual -eq $planJsonExpected) "PLAN_JSON_MISMATCH" "generated plan.json differs from frozen vector"
Write-Host "PASS: plan.json exact match" -ForegroundColor Green
'@

$newBlock = @'
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

$planJsonActual = ToCanonJson $plan
$planJsonExpected = Read-Utf8NoBom $PlanPath

Require ($planJsonActual -eq $planJsonExpected) "PLAN_JSON_MISMATCH" "generated plan.json differs from frozen vector"
Write-Host "PASS: plan.json exact match" -ForegroundColor Green
'@

if($txt.IndexOf($oldBlock,[System.StringComparison]::Ordinal) -lt 0){
  Die "PATCH_TARGET_BLOCK_NOT_FOUND" "plan.json compare block"
}

$txt2 = $txt.Replace($oldBlock,$newBlock)

Write-Utf8NoBomLf -Path $Target -Text $txt2
Parse-GateFile $Target

Write-Output ("PATCH_OK TARGET=" + $Target)