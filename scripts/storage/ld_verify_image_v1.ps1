param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$ImagePath,
  [Parameter(Mandatory=$true)][string]$ManifestPath
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
  }
  finally {
    $sha.Dispose()
  }

  return (($hash | ForEach-Object { $_.ToString("x2") }) -join "")
}

function HexSha256TextLf([string]$Text){
  if($null -eq $Text){ $Text = "" }

  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }

  return (HexSha256Bytes ([Text.Encoding]::UTF8.GetBytes($t)))
}

function HexSha256File([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die "VERIFY_FAIL_IMAGE_MISSING" $Path
  }

  $h = Get-FileHash -Algorithm SHA256 -LiteralPath $Path
  return $h.Hash.ToLower()
}

function Has-Prop([object]$Obj,[string]$Name){
  if($null -eq $Obj){ return $false }
  if($null -eq $Obj.PSObject){ return $false }
  if($null -eq $Obj.PSObject.Properties){ return $false }
  return (@($Obj.PSObject.Properties.Name) -contains $Name)
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

  if($Value.PSObject -and $Value.PSObject.Properties){
    $names = @($Value.PSObject.Properties.Name | Sort-Object)
    $o = [ordered]@{}
    foreach($n in $names){
      $o[$n] = Canon $Value.$n
    }
    return $o
  }

  return ([string]$Value)
}

function ToCanonJson([object]$Value){
  return ((Canon $Value) | ConvertTo-Json -Depth 80 -Compress)
}

function Append-VerifyReceipt([object]$Receipt){
  $ledger = Join-Path $RepoRoot "proofs\receipts\device_verify.ndjson"

  $json = ToCanonJson $Receipt
  $hash = HexSha256TextLf $json

  $final = [ordered]@{}
  foreach($k in @($Receipt.Keys | Sort-Object)){
    $final[$k] = $Receipt[$k]
  }
  $final["receipt_hash"] = $hash

  Append-Utf8NoBomLf -Path $ledger -Text (ToCanonJson $final)
  return $hash
}

function Emit-Fail([string]$Code,[string]$Detail){
  $receipt = [ordered]@{
    schema = "ld.device.verify.receipt.v1"
    event_type = "ld.device.verify.receipt.v1"
    ok = $false
    repo_root = $RepoRoot
    device_id = ""
    disk_number = $null
    image_path = $ImagePath
    manifest_path = $ManifestPath
    chunk_size_bytes = 0
    image_sha256 = "0000000000000000000000000000000000000000000000000000000000000000"
    chunk_count = 0
    verification_result = $Code
  }

  try {
    [void](Append-VerifyReceipt -Receipt $receipt)
  }
  catch {
    Write-Output ("LD_VERIFY_IMAGE_FAIL:" + $Code + ":" + $Detail + ":RECEIPT_APPEND_FAIL:" + $_.Exception.Message)
    exit 1
  }

  Write-Output ("LD_VERIFY_IMAGE_FAIL:" + $Code + ":" + $Detail)
  exit 1
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path

if(-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)){
  Emit-Fail "VERIFY_FAIL_IMAGE_MISSING" $ImagePath
}
if(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)){
  Emit-Fail "VERIFY_FAIL_MANIFEST_MISSING" $ManifestPath
}

$ImagePath = (Resolve-Path -LiteralPath $ImagePath).Path
$ManifestPath = (Resolve-Path -LiteralPath $ManifestPath).Path

$manifest = $null
try {
  $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
}
catch {
  Emit-Fail "VERIFY_FAIL_MANIFEST_SCHEMA" $_.Exception.Message
}

if($null -eq $manifest){
  Emit-Fail "VERIFY_FAIL_MANIFEST_SCHEMA" "manifest parsed to null"
}

if(-not (Has-Prop $manifest "image_sha256")){
  Emit-Fail "VERIFY_FAIL_MANIFEST_SCHEMA" "missing image_sha256"
}

$expectedImageHash = ([string]$manifest.image_sha256).ToLower()
if([string]::IsNullOrWhiteSpace($expectedImageHash)){
  Emit-Fail "VERIFY_FAIL_MANIFEST_SCHEMA" "blank image_sha256"
}

$chunkSize = 0
if(Has-Prop $manifest "chunk_size_bytes"){
  $chunkSize = [int]$manifest.chunk_size_bytes
}
if($chunkSize -lt 1){
  Emit-Fail "VERIFY_FAIL_MANIFEST_SCHEMA" "bad chunk_size_bytes"
}

$expectedChunks = @()
if(Has-Prop $manifest "chunks"){
  $expectedChunks = @($manifest.chunks)
}

$expectedCount = 0
if(Has-Prop $manifest "chunk_count"){
  $expectedCount = [int]$manifest.chunk_count
}
else {
  $expectedCount = [int]$expectedChunks.Count
}

if($expectedChunks.Count -ne $expectedCount){
  Emit-Fail "VERIFY_FAIL_CHUNK_COUNT" ("manifest_chunks=" + $expectedChunks.Count + " manifest_chunk_count=" + $expectedCount)
}

$actualRows = @()
$fs = [IO.File]::Open($ImagePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
try {
  $buffer = New-Object byte[] $chunkSize
  $offset = [UInt64]0

  while($true){
    $read = $fs.Read($buffer,0,$buffer.Length)
    if($read -le 0){ break }

    $actual = New-Object byte[] $read
    [Array]::Copy($buffer,$actual,$read)

    $actualRows += ,([ordered]@{
      index = [int]$actualRows.Count
      offset = [UInt64]$offset
      size_bytes = [int]$read
      sha256 = (HexSha256Bytes $actual)
    })

    $offset = $offset + [UInt64]$read
  }
}
finally {
  $fs.Dispose()
}

if($actualRows.Count -ne $expectedCount){
  Emit-Fail "VERIFY_FAIL_CHUNK_COUNT" ("actual=" + $actualRows.Count + " expected=" + $expectedCount)
}

for($i = 0; $i -lt $expectedCount; $i++){
  $a = $actualRows[$i]
  $e = $expectedChunks[$i]

  if([UInt64]$a.offset -ne [UInt64]$e.offset){
    Emit-Fail "VERIFY_FAIL_CHUNK_OFFSET" ("index=" + $i)
  }

  if([int]$a.size_bytes -ne [int]$e.size_bytes){
    Emit-Fail "VERIFY_FAIL_CHUNK_SIZE" ("index=" + $i)
  }

  if([string]$a.sha256 -ne [string]$e.sha256){
    Emit-Fail "VERIFY_FAIL_CHUNK_HASH" ("index=" + $i)
  }
}

$actualImageHash = HexSha256File $ImagePath
if($actualImageHash -ne $expectedImageHash){
  Emit-Fail "VERIFY_FAIL_IMAGE_HASH" ("actual=" + $actualImageHash + " expected=" + $expectedImageHash)
}

if(Has-Prop $manifest "source_size_bytes"){
  $sum = [UInt64]0
  foreach($r in @($actualRows)){
    $sum = $sum + [UInt64]$r.size_bytes
  }

  if($sum -ne [UInt64]$manifest.source_size_bytes){
    Emit-Fail "VERIFY_FAIL_EXTRA_BYTES" ("actual_sum=" + $sum + " expected=" + [UInt64]$manifest.source_size_bytes)
  }
}

$byteRanges = $null
if(Has-Prop $manifest "byte_ranges"){
  $byteRanges = $manifest.PSObject.Properties["byte_ranges"].Value
}

if($null -ne $byteRanges){
  $fileSize = (Get-Item -LiteralPath $ImagePath).Length

  foreach($r in @($byteRanges)){
    if(($r.offset -lt 0) -or ($r.length -le 0)){
      Emit-Fail "VERIFY_FAIL_INVALID_RANGE" "bad range"
    }

    if(($r.offset + $r.length) -gt $fileSize){
      Emit-Fail "VERIFY_FAIL_RANGE_OUT_OF_BOUNDS" "range exceeds image"
    }
  }
}

$receipt = [ordered]@{
  schema = "ld.device.verify.receipt.v1"
  event_type = "ld.device.verify.receipt.v1"
  ok = $true
  repo_root = $RepoRoot
  device_id = $(if(Has-Prop $manifest "device_id"){ [string]$manifest.device_id } else { "" })
  disk_number = $(if(Has-Prop $manifest "disk_number"){ $manifest.disk_number } else { $null })
  image_path = $ImagePath
  manifest_path = $ManifestPath
  chunk_size_bytes = [int]$chunkSize
  image_sha256 = [string]$actualImageHash
  chunk_count = [int]$actualRows.Count
  verification_result = "VERIFY_OK"
}

$receiptHash = Append-VerifyReceipt -Receipt $receipt

Write-Host ("VERIFY_RECEIPT_HASH: " + $receiptHash) -ForegroundColor Green
Write-Output (ToCanonJson $receipt)
Write-Output "LD_VERIFY_IMAGE_OK"
