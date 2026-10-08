param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$SourceRoot,
  [int]$MaxFiles = 1000,
  [Int64]$MaxBytes = 1073741824
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Die([string]$Code,[string]$Detail){ throw ($Code + ":" + $Detail) }

$ReceiptsLib = Join-Path $PSScriptRoot "..\storage\_lib_ld_receipts_v1.ps1"
if(-not (Test-Path -LiteralPath $ReceiptsLib -PathType Leaf)){ Die "RECEIPT_LIBRARY_MISSING" $ReceiptsLib }
. $ReceiptsLib

function EnsureDir([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  EnsureDir (Split-Path -Parent $Path)
  $normalized = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $normalized.EndsWith("`n")){ $normalized += "`n" }
  [IO.File]::WriteAllText($Path,$normalized,[Text.UTF8Encoding]::new($false))
}

function RelativePath([string]$Root,[string]$Path){
  $prefix = $Root.TrimEnd("\") + "\"
  if(-not $Path.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){
    Die "MEDIA_PATH_OUTSIDE_SOURCE" $Path
  }
  return $Path.Substring($prefix.Length).Replace("\","/")
}

function ClassifyMedia([string]$RelativePath){
  $normalized = $RelativePath.Replace("\","/")
  $lower = $normalized.ToLowerInvariant()
  $extension = [IO.Path]::GetExtension($lower)

  if($lower.StartsWith("ipod_control/")){
    return [ordered]@{ category="apple_ipod_library"; format_hint="apple.ipod_control.file"; basis="path" }
  }
  if($lower.StartsWith("video_ts/") -and @(".ifo",".bup",".vob") -contains $extension){
    return [ordered]@{ category="dvd_video"; format_hint=("dvd.video" + $extension); basis="path_and_extension" }
  }
  if(@(".mp3",".m4a",".aac",".alac",".flac",".wav",".aif",".aiff",".ogg",".wma") -contains $extension){
    return [ordered]@{ category="audio"; format_hint=("audio" + $extension); basis="extension" }
  }
  if(@(".nes",".sfc",".smc",".gb",".gbc",".gba",".n64",".z64",".v64",".nds",".3ds") -contains $extension){
    return [ordered]@{ category="rom_candidate"; format_hint=("rom" + $extension); basis="extension" }
  }
  if($extension -eq ".cos"){
    return [ordered]@{ category="cos_artifact"; format_hint="opaque.cos"; basis="extension" }
  }
  if(@(".iso",".img",".nrg",".mdf") -contains $extension){
    return [ordered]@{ category="optical_image"; format_hint=("optical" + $extension); basis="extension" }
  }
  return [ordered]@{ category="generic_file"; format_hint="opaque.file"; basis="none" }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$SourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
if($MaxFiles -lt 1){ Die "MAX_FILES_INVALID" ([string]$MaxFiles) }
if($MaxBytes -lt 1){ Die "MAX_BYTES_INVALID" ([string]$MaxBytes) }

$discovered = @(
  Get-ChildItem -LiteralPath $SourceRoot -File -Recurse -Force -ErrorAction Stop |
    Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
    Sort-Object @{ Expression={ RelativePath -Root $SourceRoot -Path $_.FullName }; Ascending=$true }
)

$rows = @()
$totalBytes = [Int64]0
$truncated = $false
foreach($file in $discovered){
  if($rows.Count -ge $MaxFiles){ $truncated = $true; break }
  $length = [Int64]$file.Length
  if(($totalBytes + $length) -gt $MaxBytes){ $truncated = $true; break }

  $relative = RelativePath -Root $SourceRoot -Path $file.FullName
  $classification = ClassifyMedia $relative
  $rows += ,([ordered]@{
    relative_path = $relative
    size_bytes = $length
    sha256 = LDREC-HexSha256File $file.FullName
    category = [string]$classification.category
    format_hint = [string]$classification.format_hint
    classification_basis = [string]$classification.basis
    recovery_action = "PRESERVE_OPAQUE_BYTES"
  })
  $totalBytes += $length
}

$countMap = @{}
foreach($row in $rows){
  $category = [string]$row.category
  if(-not $countMap.ContainsKey($category)){ $countMap[$category] = 0 }
  $countMap[$category] = [int]$countMap[$category] + 1
}
$categoryCounts = [ordered]@{}
foreach($category in @($countMap.Keys | Sort-Object)){ $categoryCounts[$category] = [int]$countMap[$category] }

$canonicalCatalog = [ordered]@{
  schema = "ld.media.catalog.content.v1"
  max_files = $MaxFiles
  max_bytes = $MaxBytes
  truncated = [bool]$truncated
  file_count = [int]$rows.Count
  total_bytes = [Int64]$totalBytes
  category_counts = $categoryCounts
  files = @($rows)
}
$catalogSha256 = LDREC-HexSha256TextLf (LDREC-ToCanonJson $canonicalCatalog)

$receipt = [ordered]@{
  schema = "ld.media.catalog.receipt.v1"
  event_type = "ld.media.catalog.receipt.v1"
  ok = $true
  availability = "available"
  repo_root = $RepoRoot
  source_root = $SourceRoot
  mode = "mounted_media_catalog"
  destructive = $false
  writes_source = $false
  performs_copy = $false
  hashes_file_contents = $true
  bounded = $true
  max_files = $MaxFiles
  max_bytes = $MaxBytes
  truncated = [bool]$truncated
  file_count = [int]$rows.Count
  total_bytes = [Int64]$totalBytes
  category_counts = $categoryCounts
  files = @($rows)
  catalog_sha256 = $catalogSha256
  created_utc = [DateTime]::UtcNow.ToString("o")
}

$outDir = Join-Path $RepoRoot "proofs\receipts\media_catalog"
$outPath = Join-Path $outDir ("media_catalog_" + [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff") + ".json")
$json = $receipt | ConvertTo-Json -Depth 100 -Compress
Write-Utf8NoBomLf -Path $outPath -Text $json

Write-Output ("MEDIA_CATALOG_PATH: " + $outPath)
Write-Output ("MEDIA_CATALOG_FILES: " + [string]$rows.Count)
Write-Output $json
Write-Output "LD_MEDIA_CATALOG_OK"
