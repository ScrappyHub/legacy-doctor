param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){ throw ($Code + ":" + $Detail) }
function Require([bool]$Condition,[string]$Code,[string]$Detail){ if(-not $Condition){ Die $Code $Detail } }

function EnsureDir([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Write-Fixture([string]$Root,[string]$RelativePath,[string]$Payload){
  $path = Join-Path $Root $RelativePath
  EnsureDir (Split-Path -Parent $path)
  [IO.File]::WriteAllBytes($path,[Text.Encoding]::UTF8.GetBytes($Payload))
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$fixtureBase = Join-Path $RepoRoot "proofs\selftest\media_catalog_fixture"
$allowedPrefix = [IO.Path]::GetFullPath((Join-Path $RepoRoot "proofs\selftest")).TrimEnd("\") + "\"
$resolvedFixture = [IO.Path]::GetFullPath($fixtureBase)
Require ($resolvedFixture.StartsWith($allowedPrefix,[StringComparison]::OrdinalIgnoreCase)) "FIXTURE_PATH_OUTSIDE_SELFTEST" $resolvedFixture
if(Test-Path -LiteralPath $resolvedFixture){ Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }

$source = Join-Path $resolvedFixture "source"
$destination = Join-Path $resolvedFixture "destination"
EnsureDir $source
EnsureDir $destination

Write-Fixture $source "iPod_Control\Music\F00\ABCD.m4a" "fixture-ipod-audio"
Write-Fixture $source "VIDEO_TS\VIDEO_TS.IFO" "fixture-dvd-ifo"
Write-Fixture $source "VIDEO_TS\VTS_01_1.VOB" "fixture-dvd-vob"
Write-Fixture $source "ROMS\example.nes" "fixture-rom"
Write-Fixture $source "archive\device.cos" "fixture-cos"
Write-Fixture $source "disc\legacy.iso" "fixture-optical-image"
Write-Fixture $source "notes\readme.txt" "fixture-generic"

$libraryPath = Join-Path $RepoRoot "scripts\storage\_lib_ld_receipts_v1.ps1"
$catalogScript = Join-Path $RepoRoot "scripts\media\ld_media_catalog_v1.ps1"
if(-not (Test-Path -LiteralPath $libraryPath -PathType Leaf)){ Die "RECEIPT_LIBRARY_MISSING" $libraryPath }
if(-not (Test-Path -LiteralPath $catalogScript -PathType Leaf)){ Die "MEDIA_CATALOG_SCRIPT_MISSING" $catalogScript }
. $libraryPath

function Run-Catalog([int]$MaxFiles){
  $output = & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $catalogScript -RepoRoot $RepoRoot -SourceRoot $source -MaxFiles $MaxFiles -MaxBytes 1048576
  if($LASTEXITCODE -ne 0){ Die "MEDIA_CATALOG_EXIT_NONZERO" ([string]$LASTEXITCODE) }
  return (LDREC-ReadReceiptFromOutput -Output $output -ExpectedSchema "ld.media.catalog.receipt.v1" -SchemaDirectory (Join-Path $RepoRoot "schemas"))
}

$first = Run-Catalog 20
Require ([bool]$first.ok) "CATALOG_NOT_OK" ""
Require (-not [bool]$first.truncated) "CATALOG_UNEXPECTED_TRUNCATION" ""
Require ([int]$first.file_count -eq 7) "CATALOG_FILE_COUNT_BAD" ([string]$first.file_count)
Require ([int]$first.category_counts.apple_ipod_library -eq 1) "IPOD_CLASSIFICATION_BAD" ""
Require ([int]$first.category_counts.dvd_video -eq 2) "DVD_CLASSIFICATION_BAD" ""
Require ([int]$first.category_counts.rom_candidate -eq 1) "ROM_CLASSIFICATION_BAD" ""
Require ([int]$first.category_counts.cos_artifact -eq 1) "COS_CLASSIFICATION_BAD" ""
Require ([int]$first.category_counts.optical_image -eq 1) "OPTICAL_CLASSIFICATION_BAD" ""
Require ([int]$first.category_counts.generic_file -eq 1) "GENERIC_CLASSIFICATION_BAD" ""

foreach($row in @($first.files)){
  $relativeWindows = ([string]$row.relative_path).Replace("/","\")
  $sourcePath = Join-Path $source $relativeWindows
  $destinationPath = Join-Path $destination $relativeWindows
  EnsureDir (Split-Path -Parent $destinationPath)
  [IO.File]::Copy($sourcePath,$destinationPath,$true)

  $sourceHash = LDREC-HexSha256File $sourcePath
  $destinationHash = LDREC-HexSha256File $destinationPath
  Require ($sourceHash -ceq [string]$row.sha256) "SOURCE_HASH_CHANGED" ([string]$row.relative_path)
  Require ($destinationHash -ceq $sourceHash) "BACKUP_HASH_MISMATCH" ([string]$row.relative_path)
}

$destinationFiles = @(Get-ChildItem -LiteralPath $destination -File -Recurse)
Require ($destinationFiles.Count -eq 7) "BACKUP_FILE_COUNT_BAD" ([string]$destinationFiles.Count)

$second = Run-Catalog 20
Require (([string]$second.catalog_sha256) -ceq ([string]$first.catalog_sha256)) "CATALOG_NOT_DETERMINISTIC" (([string]$first.catalog_sha256) + ":" + [string]$second.catalog_sha256)

$bounded = Run-Catalog 3
Require ([bool]$bounded.truncated) "BOUNDED_CATALOG_NOT_TRUNCATED" ""
Require ([int]$bounded.file_count -eq 3) "BOUNDED_CATALOG_COUNT_BAD" ([string]$bounded.file_count)

Write-Output "PASS: mounted media catalog classified representative fixtures"
Write-Output "PASS: fixture backup reproduced every file with matching SHA-256"
Write-Output "PASS: catalog hash is deterministic and bounds truncate explicitly"
Write-Output "SELFTEST_LD_MEDIA_CATALOG_BACKUP_FIXTURE_OK"
