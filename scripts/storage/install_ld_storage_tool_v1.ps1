param(
  [Parameter(Mandatory=$true)][string]$RepoRoot,
  [string]$SourceToolPath
)
$ErrorActionPreference = 'Stop' 
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if([string]::IsNullOrWhiteSpace($p)){ return }; if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Utf8NoBom(){ New-Object System.Text.UTF8Encoding($false) }
function WriteUtf8Lf([string]$path,[string]$text){ EnsureDir (Split-Path -Parent $path); $cr=[char]13; $lf=[char]10; $s=$text.Replace(($cr.ToString()+$lf.ToString()),$lf.ToString()).Replace($cr.ToString(),$lf.ToString()); if(-not $s.EndsWith($lf.ToString())){ $s+=$lf.ToString() }; [IO.File]::WriteAllText($path,$s,(Utf8NoBom)) }
function ParseGateFile([string]$path){ try { [void][ScriptBlock]::Create((Get-Content -Raw -LiteralPath $path -Encoding UTF8)) } catch { throw ('PARSE_GATE_FAIL: ' + $path + [char]10 + $_.Exception.Message) } }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot 'scripts\storage' 
$Target = Join-Path $ScriptsDir 'ld_storage_v1.ps1' 
EnsureDir $ScriptsDir

if([string]::IsNullOrWhiteSpace($SourceToolPath)){ $here = Split-Path -Parent $MyInvocation.MyCommand.Path; $SourceToolPath = Join-Path $here 'ld_storage_v1.ps1' }
if(-not (Test-Path -LiteralPath $SourceToolPath)){ Die ('MISSING_SOURCE_TOOL: ' + $SourceToolPath) }
$txt = Get-Content -Raw -LiteralPath $SourceToolPath -Encoding UTF8
WriteUtf8Lf $Target $txt
ParseGateFile $Target
Write-Host ('INSTALL_OK: ' + $Target) -ForegroundColor Green
