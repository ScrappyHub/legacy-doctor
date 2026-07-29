param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$ImagePath,
  [ValidateSet("full_copy","byte_ranges")][string]$Mode = "full_copy",
  [string]$RangesJsonPath = ""
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

function Append-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ EnsureDir $dir }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::AppendAllText($Path,$t,(Utf8NoBom))
}

function HexSha256Bytes([byte[]]$Bytes){
  if($null -eq $Bytes){ $Bytes = [byte[]]@() }

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($Bytes)
  } finally {
    $sha.Dispose()
  }

  $sb = New-Object System.Text.StringBuilder
  foreach($b in $hash){
    [void]$sb.Append($b.ToString("x2"))
  }
  return $sb.ToString()
}

function HexSha256TextLf([string]$Text){
  if($null -eq $Text){ $Text = "" }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  return (HexSha256Bytes ([Text.Encoding]::UTF8.GetBytes($t)))
}

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
    foreach($x in @($Value)){
      $arr += ,(Canon $x)
    }
    return ,$arr
  }

  return ([string]$Value)
}

function ToCanonJson([object]$Value){
  return ((Canon $Value) | ConvertTo-Json -Depth 60 -Compress)
}

function Append-Receipt([string]$LedgerPath,[hashtable]$Receipt){
  $json = ToCanonJson $Receipt
  $hash = HexSha256TextLf $json

  $final = [ordered]@{}
  foreach($k in @($Receipt.Keys | Sort-Object)){
    $final[$k] = $Receipt[$k]
  }
  $final["receipt_hash"] = $hash

  Append-Utf8NoBomLf $LedgerPath (ToCanonJson $final)
  return $hash
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ImagePath = (Resolve-Path -LiteralPath $ImagePath).Path

$ExtractLib = Join-Path $RepoRoot "scripts\storage\_lib_ld_extract_v1.ps1"
$SchemaPath = Join-Path $RepoRoot "schemas\ld.device.extract.receipt.v1.json"

foreach($p in @($ExtractLib,$SchemaPath)){
  if(-not (Test-Path -LiteralPath $p -PathType Leaf)){
    Die "MISSING_DEP" $p
  }
}

. $ExtractLib

$OutRoot = Join-Path $RepoRoot "proofs\extract"
EnsureDir $OutRoot

$stamp = [DateTime]::UtcNow.ToString("yyyyMMdd_HHmmss_fff")
$base = "extract_" + $stamp
$RunDir = Join-Path $OutRoot $base
EnsureDir $RunDir

$manifestPath = Join-Path $RunDir ($base + ".manifest.json")
$ledgerPath = Join-Path $RepoRoot "proofs\receipts\device_extract.ndjson"

$outputs = @()

if($Mode -eq "full_copy"){
  $outPath = Join-Path $RunDir "full_copy.img"
  $full = LDEXTRACT-ExtractFullCopy -ImagePath $ImagePath -OutPath $outPath
  $outputs = @($full)
}
elseif($Mode -eq "byte_ranges"){
  if([string]::IsNullOrWhiteSpace($RangesJsonPath)){
    Die "RANGES_JSON_REQUIRED" "RangesJsonPath required for byte_ranges"
  }

  $RangesJsonPath = (Resolve-Path -LiteralPath $RangesJsonPath).Path
  $raw = Get-Content -LiteralPath $RangesJsonPath -Raw -Encoding UTF8
  $parsed = $raw | ConvertFrom-Json
  $ranges = @($parsed.ranges)

  $rangeRoot = Join-Path $RunDir "ranges"
  $outputs = @(LDEXTRACT-ExtractByteRanges -ImagePath $ImagePath -Ranges $ranges -OutRoot $rangeRoot)
}
else {
  Die "BAD_MODE" $Mode
}

$manifest = [ordered]@{
  schema = "ld.device.extract.manifest.v1"
  repo_root = $RepoRoot
  image_path = $ImagePath
  mode = $Mode
  output_count = [int]$outputs.Count
  outputs = @($outputs)
}

Write-Utf8NoBomLf $manifestPath (ToCanonJson $manifest)

$receipt = [ordered]@{
  schema = "ld.device.extract.receipt.v1"
  event_type = "ld.device.extract.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  device_id = ""
  disk_number = $null
  image_path = $ImagePath
  manifest_path = $manifestPath
  extract_root = $RunDir
  mode = $Mode
  output_count = [int]$outputs.Count
}

$receiptHash = Append-Receipt -LedgerPath $ledgerPath -Receipt $receipt

Write-Host ("EXTRACT_ROOT: " + $RunDir) -ForegroundColor Green
Write-Host ("EXTRACT_MANIFEST: " + $manifestPath) -ForegroundColor Green
Write-Host ("EXTRACT_RECEIPT_HASH: " + $receiptHash) -ForegroundColor Green
Write-Output (ToCanonJson $receipt)
Write-Output "LD_EXTRACT_IMAGE_OK"