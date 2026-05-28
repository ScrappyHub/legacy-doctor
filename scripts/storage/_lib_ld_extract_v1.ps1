param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function LDEXTRACT-Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function LDEXTRACT-Utf8NoBom(){
  return (New-Object System.Text.UTF8Encoding($false))
}

function LDEXTRACT-EnsureDir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ return }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function LDEXTRACT-WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ LDEXTRACT-EnsureDir $dir }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($Path,$t,(LDEXTRACT-Utf8NoBom))
}

function LDEXTRACT-HexSha256Bytes([byte[]]$Bytes){
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

function LDEXTRACT-HexSha256File([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    LDEXTRACT-Die "MISSING_FILE" $Path
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

function LDEXTRACT-Canon([object]$Value){
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
      $o[$k] = LDEXTRACT-Canon $Value[$k]
    }
    return $o
  }

  if($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])){
    $arr = @()
    foreach($x in @($Value)){
      $arr += ,(LDEXTRACT-Canon $x)
    }
    return ,$arr
  }

  return ([string]$Value)
}

function LDEXTRACT-ToCanonJson([object]$Value){
  return ((LDEXTRACT-Canon $Value) | ConvertTo-Json -Depth 60 -Compress)
}

function LDEXTRACT-ExtractFullCopy(
  [string]$ImagePath,
  [string]$OutPath
){
  if(-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)){
    LDEXTRACT-Die "IMAGE_MISSING" $ImagePath
  }

  $dir = Split-Path -Parent $OutPath
  if($dir){ LDEXTRACT-EnsureDir $dir }

  Copy-Item -LiteralPath $ImagePath -Destination $OutPath -Force

  return [ordered]@{
    kind = "full_copy"
    source_offset = [UInt64]0
    size_bytes = [UInt64](Get-Item -LiteralPath $OutPath).Length
    output_path = $OutPath
    sha256 = (LDEXTRACT-HexSha256File $OutPath)
  }
}

function LDEXTRACT-ExtractByteRanges(
  [string]$ImagePath,
  [object[]]$Ranges,
  [string]$OutRoot
){
  if(-not (Test-Path -LiteralPath $ImagePath -PathType Leaf)){
    LDEXTRACT-Die "IMAGE_MISSING" $ImagePath
  }
  if($null -eq $Ranges -or @($Ranges).Count -le 0){
    LDEXTRACT-Die "RANGES_REQUIRED" "at least one byte range is required"
  }

  LDEXTRACT-EnsureDir $OutRoot
  $rows = @()

  $fs = [IO.File]::Open($ImagePath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  try {
    $imageLen = [UInt64]$fs.Length

    foreach($r in @($Ranges)){
      $name = [string]$r.name
      $offset = [UInt64]$r.offset
      $size = [UInt64]$r.size_bytes

      if([string]::IsNullOrWhiteSpace($name)){
        LDEXTRACT-Die "BAD_RANGE_NAME" "blank"
      }
      if($size -eq 0){
        LDEXTRACT-Die "BAD_RANGE_SIZE" $name
      }
      if($offset -ge $imageLen){
        LDEXTRACT-Die "RANGE_OFFSET_OOB" ($name + ": offset=" + $offset + " image_len=" + $imageLen)
      }
      if(($offset + $size) -gt $imageLen){
        LDEXTRACT-Die "RANGE_END_OOB" ($name + ": end=" + ($offset + $size) + " image_len=" + $imageLen)
      }

      $outPath = Join-Path $OutRoot ($name + ".bin")
      $dst = [IO.File]::Open($outPath,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
      try {
        [void]$fs.Seek([Int64]$offset,[IO.SeekOrigin]::Begin)
        $remaining = [UInt64]$size
        $buffer = New-Object byte[] 1048576

        while($remaining -gt 0){
          $want = $buffer.Length
          if([UInt64]$want -gt $remaining){
            $want = [int]$remaining
          }

          $read = $fs.Read($buffer,0,$want)
          if($read -le 0){
            LDEXTRACT-Die "READ_SHORT" ($name + ": remaining=" + $remaining)
          }

          $dst.Write($buffer,0,$read)
          $remaining = $remaining - [UInt64]$read
        }

        $dst.Flush()
      }
      finally {
        $dst.Dispose()
      }

      $rows += ,([ordered]@{
        kind = "byte_range"
        name = $name
        source_offset = $offset
        size_bytes = $size
        output_path = $outPath
        sha256 = (LDEXTRACT-HexSha256File $outPath)
      })
    }
  }
  finally {
    $fs.Dispose()
  }

  return @($rows)
}

function LDEXTRACT-ExportModuleInfo(){
  return [ordered]@{
    schema = "ld.extract.lib.info.v1"
    name = "_lib_ld_extract_v1.ps1"
    provides = @(
      "LDEXTRACT-WriteUtf8NoBomLf",
      "LDEXTRACT-HexSha256Bytes",
      "LDEXTRACT-HexSha256File",
      "LDEXTRACT-ToCanonJson",
      "LDEXTRACT-ExtractFullCopy",
      "LDEXTRACT-ExtractByteRanges"
    )
  }
}