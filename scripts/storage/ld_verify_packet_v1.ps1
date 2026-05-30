param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$PacketRoot
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

function Append-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
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
  return (($hash | ForEach-Object { $_.ToString("x2") }) -join "")
}

function HexSha256File([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "VERIFY_PACKET_FAIL_SHA256SUMS_FILE_MISSING" $Path
  }
  $h = Get-FileHash -Algorithm SHA256 -LiteralPath $Path
  return $h.Hash.ToLower()
}

function ComputePacketId([string]$ManifestPath){
  if(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)){
    Die "VERIFY_PACKET_FAIL_MISSING_MANIFEST" $ManifestPath
  }
  $bytes = [IO.File]::ReadAllBytes($ManifestPath)
  return (HexSha256Bytes $bytes)
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
  return ((Canon $Value) | ConvertTo-Json -Depth 50 -Compress)
}

function HexSha256TextLf([string]$Text){
  if($null -eq $Text){ $Text = "" }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  return (HexSha256Bytes ([Text.Encoding]::UTF8.GetBytes($t)))
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
$PacketRoot = (Resolve-Path -LiteralPath $PacketRoot).Path

$SchemaPath = Join-Path $RepoRoot "schemas\ld.packet.verify.receipt.v1.json"
if(-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)){
  Die "MISSING_SCHEMA" $SchemaPath
}

$ManifestPath = Join-Path $PacketRoot "manifest.json"
$PacketIdPath = Join-Path $PacketRoot "packet_id.txt"
$Sha256SumsPath = Join-Path $PacketRoot "sha256sums.txt"

if(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)){
  Die "VERIFY_PACKET_FAIL_MISSING_MANIFEST" $ManifestPath
}
if(-not (Test-Path -LiteralPath $PacketIdPath -PathType Leaf)){
  Die "VERIFY_PACKET_FAIL_MISSING_PACKET_ID" $PacketIdPath
}
if(-not (Test-Path -LiteralPath $Sha256SumsPath -PathType Leaf)){
  Die "VERIFY_PACKET_FAIL_MISSING_SHA256SUMS" $Sha256SumsPath
}

$ExpectedPacketId = (Get-Content -LiteralPath $PacketIdPath -Raw -Encoding UTF8).Trim().ToLower()
$ActualPacketId = ComputePacketId -ManifestPath $ManifestPath

if($ExpectedPacketId -ne $ActualPacketId){
  Die "VERIFY_PACKET_FAIL_PACKET_ID_MISMATCH" ("actual=" + $ActualPacketId + " expected=" + $ExpectedPacketId)
}

$lines = @(Get-Content -LiteralPath $Sha256SumsPath -Encoding UTF8)
foreach($line in @($lines)){
  $trim = [string]$line
  if([string]::IsNullOrWhiteSpace($trim)){ continue }

  if($trim -notmatch '^([a-f0-9]{64})  (.+)$'){
    Die "VERIFY_PACKET_FAIL_SHA256SUMS_BAD_FORMAT" $trim
  }

  $expectedHash = $matches[1]
  $rel = $matches[2]
  $target = Join-Path $PacketRoot ($rel -replace '/','\')

  if(-not (Test-Path -LiteralPath $target -PathType Leaf)){
    Die "VERIFY_PACKET_FAIL_SHA256SUMS_FILE_MISSING" $rel
  }

  $actualHash = HexSha256File $target
  if($actualHash -ne $expectedHash){
    Die "VERIFY_PACKET_FAIL_SHA256SUMS_HASH_MISMATCH" ($rel + ": actual=" + $actualHash + " expected=" + $expectedHash)
  }
}

$receipt = [ordered]@{
  schema = "ld.packet.verify.receipt.v1"
  event_type = "ld.packet.verify.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  packet_root = $PacketRoot
  packet_id = $ActualPacketId
  verification_result = "VERIFY_PACKET_OK"
}

$ledger = Join-Path $RepoRoot "proofs\receipts\packet_verify.ndjson"
$receiptHash = Append-Receipt -LedgerPath $ledger -Receipt $receipt

Write-Host ("VERIFY_PACKET_RECEIPT_HASH: " + $receiptHash) -ForegroundColor Green
Write-Host ("VERIFY_PACKET_ID: " + $ActualPacketId) -ForegroundColor Green
Write-Output (ToCanonJson $receipt)
Write-Output "LD_VERIFY_PACKET_OK"