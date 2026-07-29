param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function LDVERIFY-Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function LDVERIFY-HexSha256Bytes([byte[]]$Bytes){
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

function LDVERIFY-HexSha256File([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    LDVERIFY-Die "MISSING_FILE" $Path
  }

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $fs = [IO.File]::OpenRead($Path)
    try {
      $hash = $sha.ComputeHash($fs)
    } finally {
      $fs.Dispose()
    }
  } finally {
    $sha.Dispose()
  }

  $sb = New-Object System.Text.StringBuilder
  foreach($b in $hash){
    [void]$sb.Append($b.ToString("x2"))
  }
  return $sb.ToString()
}

function LDVERIFY-ReadManifest([string]$ManifestPath){
  if(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)){
    LDVERIFY-Die "VERIFY_FAIL_MANIFEST_MISSING" $ManifestPath
  }

  try {
    $raw = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8
    $m = $raw | ConvertFrom-Json
  } catch {
    LDVERIFY-Die "VERIFY_FAIL_MANIFEST_SCHEMA" $_.Exception.Message
  }

  if($null -eq $m){
    LDVERIFY-Die "VERIFY_FAIL_MANIFEST_SCHEMA" "manifest parsed to null"
  }

  if([string]$m.schema -ne "ld.device.backup.manifest.v1"){
    LDVERIFY-Die "VERIFY_FAIL_MANIFEST_SCHEMA" ("schema=" + [string]$m.schema)
  }

  return $m
}

function LDVERIFY-VerifyImageAgainstManifest(
  [string]$ImagePath,
  [string]$ManifestPath
){
  if(-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)){
    LDVERIFY-Die "VERIFY_FAIL_IMAGE_MISSING" $ImagePath
  }

  $manifest = LDVERIFY-ReadManifest -ManifestPath $ManifestPath

  $chunkSize = [int]$manifest.chunk_size_bytes
  if($chunkSize -le 0){
    LDVERIFY-Die "VERIFY_FAIL_MANIFEST_SCHEMA" ("chunk_size_bytes=" + $chunkSize)
  }

  $expectedChunks = @($manifest.chunks)
  $expectedCount = [int]$manifest.chunk_count

  if($expectedChunks.Count -ne $expectedCount){
    LDVERIFY-Die "VERIFY_FAIL_CHUNK_COUNT" ("manifest_chunks=" + $expectedChunks.Count + " manifest_chunk_count=" + $expectedCount)
  }

  $fs = [IO.File]::Open($ImagePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  try {
    $buffer = New-Object byte[] $chunkSize
    $actualRows = @()
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
        sha256 = (LDVERIFY-HexSha256Bytes $actual)
      })

      $offset = $offset + [UInt64]$read
    }

    if($actualRows.Count -ne $expectedCount){
      LDVERIFY-Die "VERIFY_FAIL_CHUNK_COUNT" ("actual=" + $actualRows.Count + " expected=" + $expectedCount)
    }

    for($i = 0; $i -lt $expectedCount; $i++){
      $a = $actualRows[$i]
      $e = $expectedChunks[$i]

      if([UInt64]$a.offset -ne [UInt64]$e.offset){
        LDVERIFY-Die "VERIFY_FAIL_CHUNK_OFFSET" ("index=" + $i + " actual=" + [UInt64]$a.offset + " expected=" + [UInt64]$e.offset)
      }

      if([int]$a.size_bytes -ne [int]$e.size_bytes){
        LDVERIFY-Die "VERIFY_FAIL_CHUNK_SIZE" ("index=" + $i + " actual=" + [int]$a.size_bytes + " expected=" + [int]$e.size_bytes)
      }

      if([string]$a.sha256 -ne [string]$e.sha256){
        LDVERIFY-Die "VERIFY_FAIL_CHUNK_HASH" ("index=" + $i + " actual=" + [string]$a.sha256 + " expected=" + [string]$e.sha256)
      }
    }

    $actualImageHash = LDVERIFY-HexSha256File $ImagePath
    if([string]$actualImageHash -ne [string]$manifest.image_sha256){
      LDVERIFY-Die "VERIFY_FAIL_IMAGE_HASH" ("actual=" + [string]$actualImageHash + " expected=" + [string]$manifest.image_sha256)
    }

    $sum = [UInt64]0
    foreach($r in $actualRows){
      $sum = $sum + [UInt64]$r.size_bytes
    }

    if($sum -ne [UInt64]$manifest.source_size_bytes){
      LDVERIFY-Die "VERIFY_FAIL_EXTRA_BYTES" ("actual_sum=" + $sum + " expected=" + [UInt64]$manifest.source_size_bytes)
    }

    return [ordered]@{
      schema = "ld.device.verify.result.v1"
      verification_result = "VERIFY_OK"
      image_sha256 = $actualImageHash
      chunk_count = [int]$actualRows.Count
      chunk_size_bytes = $chunkSize
      manifest = $manifest
    }
  }
  finally {
    $fs.Dispose()
  }
}

function LDVERIFY-ExportModuleInfo(){
  return [ordered]@{
    schema = "ld.verify.lib.info.v1"
    name = "_lib_ld_verify_v1.ps1"
    provides = @(
      "LDVERIFY-HexSha256Bytes",
      "LDVERIFY-HexSha256File",
      "LDVERIFY-ReadManifest",
      "LDVERIFY-VerifyImageAgainstManifest"
    )
  }
}