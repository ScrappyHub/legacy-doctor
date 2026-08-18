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

function LDREC-HexSha256File([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){ LDREC-Die "HASH_FILE_MISSING" $Path }
  $stream = [IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($stream)
  } finally {
    $sha.Dispose()
    $stream.Dispose()
  }
  $builder = New-Object System.Text.StringBuilder
  foreach($byte in $hash){ [void]$builder.Append($byte.ToString("x2")) }
  return $builder.ToString()
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

function LDREC-HasProperty([object]$Value,[string]$Name){
  if($null -eq $Value){ return $false }
  return ($null -ne $Value.PSObject.Properties[$Name])
}

function LDREC-ConvertFromJson([string]$Json){
  $parameters = @{ ErrorAction = "Stop" }
  $command = Get-Command ConvertFrom-Json -ErrorAction Stop
  if($command.Parameters.ContainsKey("DateKind")){
    $parameters["DateKind"] = "String"
  }
  return ($Json | ConvertFrom-Json @parameters)
}

function LDREC-AssertJsonType([object]$Value,[string]$Type,[string]$Context){
  $integerTypes = @(
    [sbyte],[byte],[int16],[uint16],[int32],[uint32],[int64],[uint64]
  )

  $valid = switch($Type){
    "string" { $Value -is [string] }
    "boolean" { $Value -is [bool] }
    "integer" {
      $isInteger = $false
      foreach($integerType in $integerTypes){
        if($Value -is $integerType){ $isInteger = $true; break }
      }
      $isInteger
    }
    "number" {
      ($Value -is [sbyte]) -or ($Value -is [byte]) -or
      ($Value -is [int16]) -or ($Value -is [uint16]) -or
      ($Value -is [int32]) -or ($Value -is [uint32]) -or
      ($Value -is [int64]) -or ($Value -is [uint64]) -or
      ($Value -is [single]) -or ($Value -is [double]) -or ($Value -is [decimal])
    }
    "array" { ($Value -is [System.Collections.IList]) -or ($Value -is [System.Array]) }
    "object" {
      ($Value -is [System.Collections.IDictionary]) -or
      (($null -ne $Value) -and ($Value -isnot [string]) -and ($Value -isnot [System.Collections.IList]) -and ($Value -isnot [System.Array]) -and ($Value -is [psobject]))
    }
    default { LDREC-Die "RECEIPT_SCHEMA_TYPE_UNSUPPORTED" ($Context + ":" + $Type) }
  }

  if(-not $valid){ LDREC-Die "RECEIPT_PROPERTY_TYPE_INVALID" ($Context + ":expected=" + $Type) }
}

function LDREC-AssertReceiptAgainstSchema([object]$Receipt,[object]$Schema,[string]$ExpectedSchema){
  if($null -eq $Receipt){ LDREC-Die "RECEIPT_NULL" $ExpectedSchema }
  if(([string]$Schema.type) -ne "object"){ LDREC-Die "RECEIPT_SCHEMA_ROOT_NOT_OBJECT" $ExpectedSchema }
  if($Schema.additionalProperties -ne $false){ LDREC-Die "RECEIPT_SCHEMA_ROOT_NOT_CLOSED" $ExpectedSchema }

  foreach($requiredName in @($Schema.required)){
    if(-not (LDREC-HasProperty $Receipt ([string]$requiredName))){
      LDREC-Die "RECEIPT_REQUIRED_PROPERTY_MISSING" ($ExpectedSchema + ":" + [string]$requiredName)
    }
  }

  $declared = @($Schema.properties.PSObject.Properties.Name)
  foreach($actualName in @($Receipt.PSObject.Properties.Name)){
    if(-not ($declared -ccontains [string]$actualName)){
      LDREC-Die "RECEIPT_UNDECLARED_PROPERTY" ($ExpectedSchema + ":" + [string]$actualName)
    }
  }

  foreach($propertyDefinition in @($Schema.properties.PSObject.Properties)){
    $name = [string]$propertyDefinition.Name
    if(-not (LDREC-HasProperty $Receipt $name)){ continue }
    $definition = $propertyDefinition.Value
    $value = $Receipt.PSObject.Properties[$name].Value
    $context = $ExpectedSchema + ":" + $name

    if(LDREC-HasProperty $definition "type"){
      LDREC-AssertJsonType -Value $value -Type ([string]$definition.type) -Context $context
    }

    if(LDREC-HasProperty $definition "const"){
      $expectedJson = LDREC-ToCanonJson $definition.const
      $actualJson = LDREC-ToCanonJson $value
      if($actualJson -cne $expectedJson){
        LDREC-Die "RECEIPT_PROPERTY_CONST_MISMATCH" ($context + ":expected=" + $expectedJson + ":actual=" + $actualJson)
      }
    }

    if(LDREC-HasProperty $definition "enum"){
      $actualJson = LDREC-ToCanonJson $value
      $enumMatch = $false
      foreach($allowed in @($definition.enum)){
        if((LDREC-ToCanonJson $allowed) -ceq $actualJson){ $enumMatch = $true; break }
      }
      if(-not $enumMatch){ LDREC-Die "RECEIPT_PROPERTY_ENUM_MISMATCH" $context }
    }

    if((LDREC-HasProperty $definition "minimum") -and ([decimal]$value -lt [decimal]$definition.minimum)){
      LDREC-Die "RECEIPT_PROPERTY_BELOW_MINIMUM" $context
    }

    if((LDREC-HasProperty $definition "format") -and ([string]$definition.format -eq "date-time")){
      $parsed = [DateTimeOffset]::MinValue
      if(-not [DateTimeOffset]::TryParse([string]$value,[ref]$parsed)){
        LDREC-Die "RECEIPT_PROPERTY_DATETIME_INVALID" $context
      }
    }
  }

  if(([string]$Receipt.schema) -cne $ExpectedSchema){
    LDREC-Die "RECEIPT_SCHEMA_MISMATCH" ($ExpectedSchema + ":" + [string]$Receipt.schema)
  }
  if(([string]$Receipt.event_type) -cne $ExpectedSchema){
    LDREC-Die "RECEIPT_EVENT_TYPE_MISMATCH" ($ExpectedSchema + ":" + [string]$Receipt.event_type)
  }
}

function LDREC-ReadReceiptFromOutput(
  [object[]]$Output,
  [string]$ExpectedSchema,
  [string]$SchemaDirectory
){
  if($ExpectedSchema -notmatch "^[a-z0-9._-]+$"){
    LDREC-Die "RECEIPT_SCHEMA_NAME_INVALID" $ExpectedSchema
  }

  $schemaPath = Join-Path $SchemaDirectory ($ExpectedSchema + ".json")
  if(-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)){
    LDREC-Die "RECEIPT_SCHEMA_FILE_MISSING" $schemaPath
  }

  try {
    $schemaDocument = LDREC-ConvertFromJson (Get-Content -LiteralPath $schemaPath -Raw)
  } catch {
    LDREC-Die "RECEIPT_SCHEMA_JSON_INVALID" ($schemaPath + ":" + $_.Exception.Message)
  }

  $matches = @()
  foreach($line in @($Output)){
    $text = ([string]$line).Trim()
    if(-not $text.StartsWith("{")){ continue }

    try {
      $candidate = LDREC-ConvertFromJson $text
    } catch {
      if($text.Contains($ExpectedSchema)){
        LDREC-Die "RECEIPT_JSON_INVALID" ($ExpectedSchema + ":" + $_.Exception.Message)
      }
      continue
    }

    if((LDREC-HasProperty $candidate "schema") -and ([string]$candidate.schema -ceq $ExpectedSchema)){
      $matches += ,$candidate
    }
  }

  if($matches.Count -eq 0){ LDREC-Die "RECEIPT_OUTPUT_MISSING" $ExpectedSchema }
  if($matches.Count -ne 1){ LDREC-Die "RECEIPT_OUTPUT_AMBIGUOUS" ($ExpectedSchema + ":count=" + [string]$matches.Count) }

  $receipt = $matches[0]
  LDREC-AssertReceiptAgainstSchema -Receipt $receipt -Schema $schemaDocument -ExpectedSchema $ExpectedSchema
  return $receipt
}

function LDREC-RunReceiptScript(
  [string]$ScriptPath,
  [string]$RepoRoot,
  [string]$ExpectedSchema,
  [string[]]$ExtraArgs = @()
){
  if(-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)){
    LDREC-Die "RECEIPT_PRODUCER_SCRIPT_MISSING" $ScriptPath
  }

  $childArgs = @(
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy","Bypass",
    "-File",$ScriptPath,
    "-RepoRoot",$RepoRoot
  )
  foreach($extraArg in @($ExtraArgs)){ $childArgs += [string]$extraArg }

  $output = & powershell.exe @childArgs
  if($LASTEXITCODE -ne 0){
    LDREC-Die "RECEIPT_PRODUCER_EXIT_NONZERO" ($ScriptPath + ":" + [string]$LASTEXITCODE)
  }

  return (LDREC-ReadReceiptFromOutput -Output $output -ExpectedSchema $ExpectedSchema -SchemaDirectory (Join-Path $RepoRoot "schemas"))
}

function LDREC-ExportModuleInfo(){
  return [ordered]@{
    schema = "ld.receipts.lib.info.v1"
    name = "_lib_ld_receipts_v1.ps1"
    provides = @(
      "LDREC-ToCanonJson",
      "LDREC-HexSha256Bytes",
      "LDREC-HexSha256File",
      "LDREC-HexSha256TextLf",
      "LDREC-ReceiptPath",
      "LDREC-AppendReceipt",
      "LDREC-ConvertFromJson",
      "LDREC-AssertReceiptAgainstSchema",
      "LDREC-ReadReceiptFromOutput",
      "LDREC-RunReceiptScript"
    )
  }
}
