param(
  [Parameter(Mandatory=$true)][string]$RepoRoot
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Read-Utf8([string]$Path){
  if(-not (Test-Path -LiteralPath $Path -PathType Leaf)){
    Die ("MISSING_FILE: " + $Path)
  }
  return [IO.File]::ReadAllText($Path,[Text.UTF8Encoding]::new($false))
}

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir -PathType Container)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = $Text -replace "`r`n","`n" -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  [IO.File]::WriteAllText($Path,$t,[Text.UTF8Encoding]::new($false))
}

function Parse-Gate([string]$Path){
  $raw = Get-Content -Raw -LiteralPath $Path -Encoding UTF8
  [ScriptBlock]::Create($raw) | Out-Null
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Target = Join-Path $RepoRoot "scripts\storage\_lib_ld_packet_v1.ps1"
$text = Read-Utf8 $Target

$pattern = '(?s)function\s+LDPACKET-GetPacketId\s*\([^)]*\)\s*\{.*?\n\}'

$replacement = @'
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
'@

if([regex]::IsMatch($text,$pattern)){
  $newText = [regex]::Replace($text,$pattern,$replacement,1)
}
else {
  $anchor = 'function LDPACKET-ExportModuleInfo'
  if(-not $text.Contains($anchor)){
    Die "PACKET_ID_INSERT_ANCHOR_NOT_FOUND"
  }
  $newText = $text.Replace($anchor, $replacement + "`n" + $anchor)
}

Write-Utf8NoBomLf $Target $newText
Parse-Gate $Target
Write-Host "PATCH_OK: LDPACKET-GetPacketId canonicalized" -ForegroundColor Green