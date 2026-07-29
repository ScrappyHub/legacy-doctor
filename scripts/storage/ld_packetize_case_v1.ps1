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

function LD-WriteUtf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path -LiteralPath $dir)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = $Text -replace "`r`n","`n" -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($Path,$t,$enc)
}

function LD-Sha256Hex([string]$Path){
  if(-not (Test-Path -LiteralPath $Path)){
    Die "SHA256_FILE_MISSING" $Path
  }
  $h = Get-FileHash -Algorithm SHA256 -LiteralPath $Path
  return $h.Hash.ToLower()
}

function LD-ComputePacketId([string]$ManifestPath){
  if(-not (Test-Path -LiteralPath $ManifestPath)){
    Die "PACKET_MANIFEST_MISSING" $ManifestPath
  }
  $bytes = [IO.File]::ReadAllBytes($ManifestPath)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $hash = $sha.ComputeHash($bytes)
  } finally {
    $sha.Dispose()
  }
  return ($hash | ForEach-Object { $_.ToString("x2") }) -join ""
}

# --- RESOLVE ---
$RepoRoot = (Resolve-Path $RepoRoot).Path
$ImagePath = (Resolve-Path $ImagePath).Path
$ManifestPath = (Resolve-Path $ManifestPath).Path

# --- VALIDATE ---
if(-not (Test-Path $ImagePath)){ Die "IMAGE_NOT_FOUND" $ImagePath }
if(-not (Test-Path $ManifestPath)){ Die "MANIFEST_NOT_FOUND" $ManifestPath }

# --- DIRS ---
$PacketsRoot = Join-Path $RepoRoot "packets"
New-Item -ItemType Directory -Force -Path $PacketsRoot | Out-Null

$Stage = Join-Path $PacketsRoot "_stage"
if(Test-Path $Stage){ Remove-Item $Stage -Recurse -Force }
New-Item -ItemType Directory -Force -Path $Stage | Out-Null

$Payload = Join-Path $Stage "payload"
New-Item -ItemType Directory -Force -Path $Payload | Out-Null

# --- COPY ---
$imgName = Split-Path $ImagePath -Leaf
$manName = Split-Path $ManifestPath -Leaf

$stageImg = Join-Path $Payload $imgName
$stageMan = Join-Path $Payload $manName

Copy-Item $ImagePath $stageImg -Force
Copy-Item $ManifestPath $stageMan -Force

# --- MANIFEST ---
$manifest = @{
  schema = "ld.packet.manifest.v1"
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
  payload = @(
    @{ path="payload/$imgName"; sha256=(LD-Sha256Hex $stageImg) },
    @{ path="payload/$manName"; sha256=(LD-Sha256Hex $stageMan) }
  )
}

$manifestPathTemp = Join-Path $Stage "manifest.json"
LD-WriteUtf8NoBomLf $manifestPathTemp ($manifest | ConvertTo-Json -Compress -Depth 5)

# --- PACKET ID ---
$packetId = LD-ComputePacketId $manifestPathTemp

$Final = Join-Path $PacketsRoot $packetId
New-Item -ItemType Directory -Force -Path $Final | Out-Null

Move-Item $Payload (Join-Path $Final "payload")
Move-Item $manifestPathTemp (Join-Path $Final "manifest.json")

LD-WriteUtf8NoBomLf (Join-Path $Final "packet_id.txt") $packetId

# --- SHA256SUMS ---
$sum = Join-Path $Final "sha256sums.txt"
$lines = @()

Get-ChildItem -Recurse -File $Final | ForEach-Object {
  if($_.Name -eq "sha256sums.txt"){ return }
  $rel = $_.FullName.Substring($Final.Length+1).Replace("\","/")
  $lines += "$(LD-Sha256Hex $_.FullName)  $rel"
}

LD-WriteUtf8NoBomLf $sum ($lines -join "`n")

Remove-Item $Stage -Recurse -Force

Write-Host ("LD_PACKET_ID: " + $packetId) -ForegroundColor Green
Write-Host ("LD_PACKET_PATH: " + $Final) -ForegroundColor Green
Write-Host "LD_PACKETIZE_OK" -ForegroundColor Green