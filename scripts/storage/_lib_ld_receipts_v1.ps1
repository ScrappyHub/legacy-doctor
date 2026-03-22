param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function LDREC-Die([string]$Code,[string]$Detail){
  throw ($Code + ":" + $Detail)
}

function LDREC-Utf8NoBom(){
  return (New-Object System.Text.UTF8Encoding($false))
}

function LDREC-EnsureDir([string]$Path){
  if([string]::IsNullOrWhiteSpace($Path)){ return }
  if(-not (Test-Path -LiteralPath $Path -PathType Container)){
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function LDREC-WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir){ LDREC-EnsureDir $dir }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($Path,$t,(LDREC-Utf8NoBom))
}

function LDREC-AppendUtf8NoBomLf([string]$Path,[string]$Line){
  $dir = Split-Path -Parent $Path
  if($dir){ LDREC-EnsureDir $dir }
  $t = ($Line -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::AppendAllText($Path,$t,(LDREC-Utf8NoBom))
}

function LDREC-Canon([object]$Value){
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
      $o[$k] = LDREC-Canon $Value[$k]
    }
    return $o
  }

  if($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])){
    $arr = @()
    foreach($x in $Value){
      $arr += ,(LDREC-Canon $x)
    }
    return $arr
  }

  return ([string]$Value)
}

function LDREC-ToCanonJson([object]$Value){
  return ((LDREC-Canon $Value) | ConvertTo-Json -Depth 100 -Compress)
}

function LDREC-HexSha256Bytes([byte[]]$Bytes){
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

function LDREC-HexSha256TextLf([string]$Text){
  if($null -eq $Text){ $Text = "" }
  $t = ($Text -replace "`r`n","`n") -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  return (LDREC-HexSha256Bytes ([Text.Encoding]::UTF8.GetBytes($t)))
}

function LDREC-ReceiptPath([string]$RepoRoot){
  return (Join-Path $RepoRoot "proofs\receipts\ld_fat32_imagefile.ndjson")
}

function LDREC-AppendReceipt([string]$RepoRoot,[hashtable]$Receipt){
  $json = LDREC-ToCanonJson $Receipt
  $hash = LDREC-HexSha256TextLf $json

  $final = [ordered]@{}
  foreach($k in @($Receipt.Keys | Sort-Object)){
    $final[$k] = $Receipt[$k]
  }
  $final["receipt_hash"] = $hash

  $line = LDREC-ToCanonJson $final
  $path = LDREC-ReceiptPath $RepoRoot
  LDREC-AppendUtf8NoBomLf $path $line
  return $hash
}

function LDREC-ExportModuleInfo(){
  return [ordered]@{
    schema = "ld.receipts.lib.info.v1"
    name = "_lib_ld_receipts_v1.ps1"
    provides = @(
      "LDREC-ToCanonJson",
      "LDREC-HexSha256Bytes",
      "LDREC-HexSha256TextLf",
      "LDREC-ReceiptPath",
      "LDREC-AppendReceipt"
    )
  }
}
