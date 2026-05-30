param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function LDACQ-Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function LDACQ-Utf8NoBom(){
  return (New-Object System.Text.UTF8Encoding($false))
}

function LDACQ-EnsureDir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ return }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function LDACQ-WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ LDACQ-EnsureDir $dir }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($Path,$t,(LDACQ-Utf8NoBom))
}

function LDACQ-HexSha256Bytes([byte[]]$Bytes){
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

function LDACQ-HexSha256File([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    LDACQ-Die "MISSING_FILE" $Path
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

function LDACQ-Canon([object]$Value){
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
      $o[$k] = LDACQ-Canon $Value[$k]
    }
    return $o
  }

  if($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])){
    $arr = @()
    foreach($x in @($Value)){
      $arr += ,(LDACQ-Canon $x)
    }
    return ,$arr
  }

  return ([string]$Value)
}

function LDACQ-ToCanonJson([object]$Value){
  return ((LDACQ-Canon $Value) | ConvertTo-Json -Depth 50 -Compress)
}

function LDACQ-IsAdmin(){
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function LDACQ-OpenFileSourceRead([string]$SourcePath){
  try {
    return (New-Object System.IO.FileStream(
      $SourcePath,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::Read,
      [System.IO.FileShare]::ReadWrite
    ))
  } catch {
    LDACQ-Die "OPEN_SOURCE_FAIL" ($SourcePath + " :: " + $_.Exception.Message)
  }
}

function LDACQ-OpenPhysicalDriveRead([string]$DevicePath){
  if(-not (LDACQ-IsAdmin)){
    LDACQ-Die "ADMIN_REQUIRED" "physical drive acquisition requires Administrator"
  }

  try {
    return (New-Object System.IO.FileStream(
      $DevicePath,
      [System.IO.FileMode]::Open,
      [System.IO.FileAccess]::Read,
      [System.IO.FileShare]::ReadWrite
    ))
  } catch {
    LDACQ-Die "OPEN_PHYSICAL_DRIVE_FAIL" ($DevicePath + " :: " + $_.Exception.Message)
  }
}

function LDACQ-OpenSourceRead(
  [string]$SourcePath,
  [string]$SourceKind
){
  if($SourceKind -eq "image_file"){
    return (LDACQ-OpenFileSourceRead -SourcePath $SourcePath)
  }
  elseif($SourceKind -eq "physical_drive"){
    return (LDACQ-OpenPhysicalDriveRead -DevicePath $SourcePath)
  }
  else {
    LDACQ-Die "BAD_SOURCE_KIND" $SourceKind
  }
}

function LDACQ-CopyRawImage(
  [string]$SourcePath,
  [string]$SourceKind,
  [string]$DestImagePath,
  [int]$ChunkSizeBytes,
  [UInt64]$MaxBytes = 0
){
  if($ChunkSizeBytes -le 0){
    LDACQ-Die "BAD_CHUNK_SIZE" ([string]$ChunkSizeBytes)
  }

  $src = LDACQ-OpenSourceRead -SourcePath $SourcePath -SourceKind $SourceKind
  try {
    $destDir = Split-Path -Parent $DestImagePath
    if($destDir){ LDACQ-EnsureDir $destDir }

    $dst = New-Object System.IO.FileStream(
      $DestImagePath,
      [System.IO.FileMode]::Create,
      [System.IO.FileAccess]::Write,
      [System.IO.FileShare]::None
    )
    try {
      $buffer = New-Object byte[] $ChunkSizeBytes
      $chunkRows = @()
      $offset = [UInt64]0

      while($true){
        if($MaxBytes -gt 0 -and $offset -ge $MaxBytes){
          break
        }

        $want = $buffer.Length
        if($MaxBytes -gt 0){
          $remaining = [UInt64]($MaxBytes - $offset)
          if($remaining -lt [UInt64]$want){
            $want = [int]$remaining
          }
        }

        if($want -le 0){ break }

        $read = $src.Read($buffer,0,$want)
        if($read -le 0){ break }

        $actual = New-Object byte[] $read
        [Array]::Copy($buffer,$actual,$read)
        $dst.Write($actual,0,$actual.Length)

        $chunkRows += ,([ordered]@{
          index = [int]$chunkRows.Count
          offset = [UInt64]$offset
          size_bytes = [int]$read
          sha256 = (LDACQ-HexSha256Bytes $actual)
        })

        $offset = $offset + [UInt64]$read
      }

      $dst.Flush()

      return [ordered]@{
        source_size_bytes = [UInt64]$offset
        chunk_count = [int]$chunkRows.Count
        chunks = @($chunkRows)
      }
    } finally {
      $dst.Dispose()
    }
  } finally {
    $src.Dispose()
  }
}

function LDACQ-ExportModuleInfo(){
  return [ordered]@{
    schema = "ld.acquire.lib.info.v1"
    name = "_lib_ld_acquire_v1.ps1"
    provides = @(
      "LDACQ-WriteUtf8NoBomLf",
      "LDACQ-HexSha256Bytes",
      "LDACQ-HexSha256File",
      "LDACQ-ToCanonJson",
      "LDACQ-IsAdmin",
      "LDACQ-CopyRawImage"
    )
  }
}