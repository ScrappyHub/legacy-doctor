param([Parameter(Mandatory=$true)][string]$RepoRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"
function Die([string]$Code,[string]$Detail){throw($Code+":"+$Detail)}
function Require([bool]$Condition,[string]$Code,[string]$Detail){if(-not$Condition){Die $Code $Detail}}

# Static repository conformance. It never touches a device and never writes.
$RepoRoot=(Resolve-Path -LiteralPath $RepoRoot).Path
$schemaDir=Join-Path $RepoRoot "schemas"
$selfName=[IO.Path]::GetFileName($MyInvocation.MyCommand.Path)

$lanes=@()
$lanes+=@(Get-ChildItem -LiteralPath (Join-Path $RepoRoot "scripts\storage") -File -Filter "ld_*.ps1")
$lanes+=@(Get-ChildItem -LiteralPath (Join-Path $RepoRoot "scripts\media") -File -Filter "ld_*.ps1")
Require ($lanes.Count -gt 0) "NO_LANES_FOUND" ""

$testText=""
foreach($test in @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot "scripts\selftest") -File -Filter "*.ps1")){
  if($test.Name -ne $selfName){ $testText+=[IO.File]::ReadAllText($test.FullName)+"`n" }
}

# Only the quarantined formatter may reference destructive primitives, and only after its quarantine guard.
$destructive="LD-WriteSectors?|LD-WriteBytes|LD-OpenRawDiskReadWrite|Format-Volume|Clear-Disk|Initialize-Disk|New-Partition|Remove-Partition|Set-Partition|Set-Disk|diskpart|Add-PartitionAccessPath|Remove-PartitionAccessPath|Set-Volume\b"
$quarantined=@("ld_format_fat32_owned_v1")

$problems=@()
foreach($lane in $lanes){
  $text=[IO.File]::ReadAllText($lane.FullName)

  if(-not $testText.Contains($lane.BaseName)){ $problems+=("LANE_WITHOUT_SELFTEST:"+$lane.BaseName) }

  foreach($match in [regex]::Matches($text,'schema\s*=\s*"(ld\.[A-Za-z0-9_.]+\.receipt\.v1)"')){
    $schemaName=$match.Groups[1].Value
    $schemaPath=Join-Path $schemaDir ($schemaName+".json")
    if(-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)){ $problems+=("RECEIPT_SCHEMA_MISSING:"+$lane.BaseName+":"+$schemaName); continue }
    $schema=Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json
    if([string]$schema.properties.schema.const -cne $schemaName){ $problems+=("RECEIPT_SCHEMA_CONST_MISMATCH:"+$schemaName) }
  }

  $destructiveMatch=[regex]::Match($text,$destructive)
  if($destructiveMatch.Success){
    if($quarantined -notcontains $lane.BaseName){
      $problems+=("DESTRUCTIVE_PRIMITIVE_IN_LANE:"+$lane.BaseName+":"+$destructiveMatch.Value)
    } else {
      $guardIndex=$text.IndexOf("CAPABILITY_QUARANTINED",[StringComparison]::Ordinal)
      if($guardIndex -lt 0 -or $guardIndex -gt $destructiveMatch.Index){ $problems+=("QUARANTINE_GUARD_NOT_FIRST:"+$lane.BaseName) }
    }
  }
}
Require ($problems.Count -eq 0) "LANE_CONFORMANCE_FAILED" ($problems -join " | ")

# Negative proof: the checker rejects a lane that has no schema file.
$syntheticText='$receipt=[ordered]@{schema="ld.synthetic.not_a_real_lane.receipt.v1"}'
$syntheticMatch=[regex]::Match($syntheticText,'schema\s*=\s*"(ld\.[A-Za-z0-9_.]+\.receipt\.v1)"')
Require $syntheticMatch.Success "SYNTHETIC_PATTERN_NOT_MATCHED" ""
Require (-not (Test-Path -LiteralPath (Join-Path $schemaDir ($syntheticMatch.Groups[1].Value+".json")) -PathType Leaf)) "SYNTHETIC_SCHEMA_UNEXPECTEDLY_PRESENT" ""

Write-Output ("PASS: "+$lanes.Count+" lane scripts each have selftest coverage")
Write-Output "PASS: every emitted receipt schema exists and its const matches"
Write-Output "PASS: destructive primitives appear only behind the formatter quarantine guard"
Write-Output "SELFTEST_LD_LANE_CONFORMANCE_OK"
