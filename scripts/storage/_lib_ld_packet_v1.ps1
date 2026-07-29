param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function LDPACKET-Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function LDPACKET-Utf8NoBom(){
  return (New-Object System.Text.UTF8Encoding($false))
}

function LDPACKET-EnsureDir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ return }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function LDPACKET-WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ LDPACKET-EnsureDir $dir }

  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }

  [IO.File]::WriteAllText($Path,$t,(LDPACKET-Utf8NoBom))
}

function LDPACKET-HexSha256Bytes([byte[]]$Bytes){
  if($null -eq $Bytes){ $Bytes = [byte[]]@() }

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($Bytes)
  }
  finally {
    $sha.Dispose()
  }

  $sb = New-Object System.Text.StringBuilder
  foreach($b in $hash){
    [void]$sb.Append($b.ToString("x2"))
  }
  return $sb.ToString()
}

function LDPACKET-HexSha256File([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    LDPACKET-Die "MISSING_FILE" $Path
  }

  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $fs = [IO.File]::OpenRead($Path)
    try {
      $hash = $sha.ComputeHash($fs)
    }
    finally {
      $fs.Dispose()
    }
  }
  finally {
    $sha.Dispose()
  }

  $sb = New-Object System.Text.StringBuilder
  foreach($b in $hash){
    [void]$sb.Append($b.ToString("x2"))
  }
  return $sb.ToString()
}

function LDPACKET-Canon([object]$Value){
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
      $o[$k] = LDPACKET-Canon $Value[$k]
    }
    return $o
  }

  if($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])){
    $arr = @()
    foreach($x in @($Value)){
      $arr += ,(LDPACKET-Canon $x)
    }
    return ,$arr
  }

  return ([string]$Value)
}

function LDPACKET-ToCanonJson([object]$Value){
  return ((LDPACKET-Canon $Value) | ConvertTo-Json -Depth 80 -Compress)
}

function LDPACKET-GetRelativePath([string]$Root,[string]$Path){
  if([string]::IsNullOrWhiteSpace($Root)){ LDPACKET-Die "BAD_ROOT" "Root is blank" }
  if([string]::IsNullOrWhiteSpace($Path)){ LDPACKET-Die "BAD_PATH" "Path is blank" }

  $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
  $resolvedPath = (Resolve-Path -LiteralPath $Path).Path

  $rootUri = New-Object System.Uri(($resolvedRoot.TrimEnd('\') + '\'))
  $pathUri = New-Object System.Uri($resolvedPath)
  $rel = $rootUri.MakeRelativeUri($pathUri).ToString()

  return ([Uri]::UnescapeDataString($rel) -replace '/','\')
}

function LDPACKET-GetFilesRecursive([string]$Root){
  if(-not (Test-Path -LiteralPath $Root -PathType Container)){
    LDPACKET-Die "MISSING_DIR" $Root
  }
  return @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName)
}

function LDPACKET-WriteSha256Sums([string]$PacketRoot){
  if(-not (Test-Path -LiteralPath $PacketRoot -PathType Container)){
    LDPACKET-Die "MISSING_PACKET_ROOT" $PacketRoot
  }

  $files = @(
    LDPACKET-GetFilesRecursive -Root $PacketRoot |
      Where-Object { $_.Name -ne "sha256sums.txt" }
  )

  $lines = @()

  foreach($f in $files){
    $rel = LDPACKET-GetRelativePath -Root $PacketRoot -Path $f.FullName
    $hash = LDPACKET-HexSha256File $f.FullName
    $lines += ($hash + " *" + $rel)
  }

  $shaPath = Join-Path $PacketRoot "sha256sums.txt"
  LDPACKET-WriteUtf8NoBomLf $shaPath ($lines -join "`n")
}

function LDPACKET-BuildPacketId([hashtable]$ManifestWithoutPacketId){
  if($null -eq $ManifestWithoutPacketId){
    LDPACKET-Die "NULL_MANIFEST" "ManifestWithoutPacketId"
  }

  if(@($ManifestWithoutPacketId.Keys) -contains "packet_id"){
    LDPACKET-Die "MANIFEST_CONTAINS_PACKET_ID" "packet_id must not be present when building PacketId"
  }

  $json = LDPACKET-ToCanonJson $ManifestWithoutPacketId
  $bytes = [Text.Encoding]::UTF8.GetBytes(($json + "`n"))
  return (LDPACKET-HexSha256Bytes $bytes)
}

function LDPACKET-GetPacketId([string]$ManifestPath){
  if(-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)){
    throw ("PACKET_MANIFEST_MISSING:" + $ManifestPath)
  }

  $raw = Get-Content -Raw -LiteralPath $ManifestPath -Encoding UTF8
  $json = $raw | ConvertFrom-Json

  $ordered = [ordered]@{}
  foreach($p in @($json.PSObject.Properties.Name | Sort-Object)){
    if($p -ne "packet_id"){
      $ordered[$p] = $json.$p
    }
  }

  $canon = ($ordered | ConvertTo-Json -Depth 100 -Compress)
  $canon = ($canon -replace "`r`n","`n") -replace "`r","`n"
  if(-not $canon.EndsWith("`n")){ $canon += "`n" }

  $bytes = [Text.Encoding]::UTF8.GetBytes($canon)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($bytes)
  }
  finally {
    $sha.Dispose()
  }

  $sb = New-Object System.Text.StringBuilder
  foreach($b in $hash){
    [void]$sb.Append($b.ToString("x2"))
  }
  return $sb.ToString()
}
function LDPACKET-ExportModuleInfo(){
  return [ordered]@{
    schema = "ld.packet.lib.info.v1"
    name = "_lib_ld_packet_v1.ps1"
    provides = @(
      "LDPACKET-WriteUtf8NoBomLf",
      "LDPACKET-HexSha256Bytes",
      "LDPACKET-HexSha256File",
      "LDPACKET-ToCanonJson",
      "LDPACKET-GetRelativePath",
      "LDPACKET-GetFilesRecursive",
      "LDPACKET-WriteSha256Sums",
      "LDPACKET-BuildPacketId"
    )
  }
}
