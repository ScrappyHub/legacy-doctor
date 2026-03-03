param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if([string]::IsNullOrWhiteSpace($p)){ return }; if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Sha256HexFile([string]$p){
  if(-not (Test-Path -LiteralPath $p)){ Die ("MISSING_FILE: " + $p) }
  $b=[IO.File]::ReadAllBytes($p)
  $sha=[System.Security.Cryptography.SHA256]::Create()
  try {
    $h=$sha.ComputeHash($b)
    $sb=New-Object System.Text.StringBuilder
    foreach($x in $h){ [void]$sb.Append($x.ToString("x2")) }
    return $sb.ToString()
  } finally { $sha.Dispose() }
}

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ToolsDir = Join-Path $RepoRoot "tools"
EnsureDir $ToolsDir
$OutPath = Join-Path $ToolsDir "fat32format.exe"

# Mirror candidates (first one that downloads wins)
$Candidates = @(
  "https://github.com/bga/fat32format/raw/master/fat32format.exe"
  "https://github.com/bga/fat32format/raw/master/fat32format.exe?raw=1"
)

if(Test-Path -LiteralPath $OutPath){ Remove-Item -LiteralPath $OutPath -Force }
$ok = $false
foreach($u in @($Candidates)){
  try {
    Write-Host ("DOWNLOADING: " + $u) -ForegroundColor Cyan
    Invoke-WebRequest -Uri $u -OutFile $OutPath -UseBasicParsing
    if((Test-Path -LiteralPath $OutPath) -and ((Get-Item -LiteralPath $OutPath).Length -gt 0)){ $ok = $true; break }
  } catch {
    if(Test-Path -LiteralPath $OutPath){ Remove-Item -LiteralPath $OutPath -Force }
  }
}
if(-not $ok){ Die "DOWNLOAD_FAILED: could not fetch fat32format.exe from candidates" }
$sha = Sha256HexFile $OutPath
Write-Host ("TOOL_OK: " + $OutPath) -ForegroundColor Green
Write-Host ("SHA256:  " + $sha) -ForegroundColor Yellow
Write-Host "NEXT: rerun ld_format_sd_fat32_v1.ps1 (it should now find tools\\fat32format.exe)." -ForegroundColor Green
