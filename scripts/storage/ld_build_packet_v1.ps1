param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [Parameter(Mandatory=$true)][string]$ImagePath,
  [Parameter(Mandatory=$true)][string]$SourceManifestPath
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Die([string]$m){ throw $m }

function Write-Utf8NoBomLf([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if($dir -and -not (Test-Path $dir)){
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }
  $t = $Text -replace "`r`n","`n" -replace "`r","`n"
  if(-not $t.EndsWith("`n")){ $t += "`n" }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$t,$enc)
}

function Sha256File([string]$p){
  (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash.ToLower()
}

function ToCanonJson([object]$obj){
  # minimal canonical: sorted keys, no whitespace
  $ordered = [ordered]@{}
  foreach($k in ($obj.PSObject.Properties.Name | Sort-Object)){
    $ordered[$k] = $obj.$k
  }
  return ($ordered | ConvertTo-Json -Depth 100 -Compress)
}

# --- RESOLVE ---
$RepoRoot = (Resolve-Path $RepoRoot).Path
$ImagePath = (Resolve-Path $ImagePath).Path
$SourceManifestPath = (Resolve-Path $SourceManifestPath).Path

if(-not (Test-Path $ImagePath)){ Die "BUILD_FAIL:IMAGE_MISSING" }
if(-not (Test-Path $SourceManifestPath)){ Die "BUILD_FAIL:MANIFEST_MISSING" }

# --- PACKET DIR ---
$ts = (Get-Date).ToUniversalTime().ToString("yyyyMMdd_HHmmss_fff")
$packetRoot = Join-Path $RepoRoot ("proofs\packets\packet_" + $ts)
$payloadDir = Join-Path $packetRoot "payload"

New-Item -ItemType Directory -Force -Path $payloadDir | Out-Null

# --- COPY PAYLOAD ---
$imgName = Split-Path $ImagePath -Leaf
$manName = "source.manifest.json"

Copy-Item -LiteralPath $ImagePath -Destination (Join-Path $payloadDir $imgName) -Force
Copy-Item -LiteralPath $SourceManifestPath -Destination (Join-Path $payloadDir $manName) -Force

# --- BUILD MANIFEST (WITHOUT packet_id) ---
$manifest = @{
  schema = "ld.packet.manifest.v1"
  created_utc = (Get-Date).ToUniversalTime().ToString("o")
  payload = @{
    image = $imgName
    source_manifest = $manName
  }
}

$canon = ToCanonJson $manifest
$manifestPath = Join-Path $packetRoot "manifest.json"
Write-Utf8NoBomLf $manifestPath $canon

# --- PACKET ID ---
$bytes = [System.Text.Encoding]::UTF8.GetBytes($canon + "`n")
$sha = [System.Security.Cryptography.SHA256]::Create()
$packetId = ($sha.ComputeHash($bytes) | ForEach-Object { $_.ToString("x2") }) -join ""

$packetIdPath = Join-Path $packetRoot "packet_id.txt"
Write-Utf8NoBomLf $packetIdPath $packetId

# --- SHA256SUMS (WRITE LAST) ---
$files = Get-ChildItem -Recurse -File -Path $packetRoot | Where-Object { $_.Name -ne "sha256sums.txt" }

$lines = @()
foreach($f in $files){
  $rel = $f.FullName.Substring($packetRoot.Length + 1).Replace("\","/")
  $h = Sha256File $f.FullName
  $lines += "$h  $rel"
}

$shaPath = Join-Path $packetRoot "sha256sums.txt"
Write-Utf8NoBomLf $shaPath ($lines -join "`n")

Write-Host "LD_PACKET_BUILD_OK" -ForegroundColor Green
Write-Host ("PACKET_ROOT=" + $packetRoot)
Write-Host ("PACKET_ID=" + $packetId)