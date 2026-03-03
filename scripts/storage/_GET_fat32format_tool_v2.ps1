param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if([string]::IsNullOrWhiteSpace($p)){ return }; if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Utf8NoBom(){ New-Object System.Text.UTF8Encoding($false) }
function WriteUtf8Lf([string]$path,[string]$text){ EnsureDir (Split-Path -Parent $path); $lf = ($text -replace "`r`n","`n") -replace "`r","`n"; if(-not $lf.EndsWith("`n")){ $lf += "`n" }; [IO.File]::WriteAllText($path,$lf,(Utf8NoBom)) }
function Sha256HexBytes([byte[]]$b){ if($null -eq $b){ $b=[byte[]]@() }; $sha=[System.Security.Cryptography.SHA256]::Create(); try { $h=$sha.ComputeHash($b); $sb=New-Object System.Text.StringBuilder; foreach($x in $h){ [void]$sb.Append($x.ToString("x2")) }; return $sb.ToString() } finally { $sha.Dispose() } }
function Sha256HexFile([string]$p){ if(-not (Test-Path -LiteralPath $p)){ Die ("MISSING_FILE: "+$p) }; return (Sha256HexBytes ([IO.File]::ReadAllBytes($p))) }
function Fetch([string]$url,[string]$out){
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls11 -bor [Net.SecurityProtocolType]::Tls
  } catch { }
  if(Test-Path -LiteralPath $out){ Remove-Item -LiteralPath $out -Force }
  $wc = New-Object System.Net.WebClient
  try { $wc.Headers.Add("User-Agent","LegacyDoctor/1.0"); $wc.DownloadFile($url,$out) } finally { $wc.Dispose() }
  if(-not (Test-Path -LiteralPath $out)){ Die ("DOWNLOAD_FAILED: " + $url) }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ToolsDir = Join-Path $RepoRoot "tools"
EnsureDir $ToolsDir
$ZipPath  = Join-Path $ToolsDir "fat32format.zip"
$ExePath  = Join-Path $ToolsDir "fat32format.exe"
$HashPath = Join-Path $ToolsDir "fat32format.sha256.txt"

# Primary source is Ridgecrop (author of the widely used FAT32 formatter).
$urls = @(
  "http://www.ridgecrop.co.uk/download/fat32format.zip"
)

$ok = $false
foreach($u in @($urls)){
  try {
    Write-Host ("DOWNLOADING: " + $u) -ForegroundColor Cyan
    Fetch $u $ZipPath
    $ok = $true
    break
  } catch {
    Write-Host ("DOWNLOAD_TRY_FAILED: " + $u + " :: " + $_.Exception.Message) -ForegroundColor Yellow
  }
}
if(-not $ok){ Die "DOWNLOAD_FAILED: could not fetch fat32format.zip from candidates" }

# Extract fat32format.exe from zip
try {
  Add-Type -AssemblyName System.IO.Compression.FileSystem | Out-Null
  $tmp = Join-Path $ToolsDir ("_tmp_extract_" + [Guid]::NewGuid().ToString("n"))
  EnsureDir $tmp
  [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath,$tmp)
  $cand = Get-ChildItem -LiteralPath $tmp -Recurse -File | Where-Object { $_.Name -ieq "fat32format.exe" } | Select-Object -First 1
  if(-not $cand){ Die "EXTRACT_FAILED: fat32format.exe not found in zip" }
  Copy-Item -LiteralPath $cand.FullName -Destination $ExePath -Force
  Remove-Item -LiteralPath $tmp -Recurse -Force
} catch {
  throw
}

if(-not (Test-Path -LiteralPath $ExePath)){ Die ("INSTALL_FAILED: missing " + $ExePath) }
$h = Sha256HexFile $ExePath
if(-not (Test-Path -LiteralPath $HashPath)){
  WriteUtf8Lf $HashPath $h
  Write-Host ("PINNED_HASH_CREATED: " + $HashPath) -ForegroundColor Yellow
  Write-Host ("fat32format.exe sha256=" + $h) -ForegroundColor Yellow
} else {
  $p = (Get-Content -Raw -LiteralPath $HashPath -Encoding UTF8).Trim()
  if($p -ne $h){ Die ("HASH_MISMATCH: pinned=" + $p + " actual=" + $h) }
  Write-Host ("HASH_OK: " + $h) -ForegroundColor Green
}
Write-Host ("TOOL_OK: " + $ExePath) -ForegroundColor Green
