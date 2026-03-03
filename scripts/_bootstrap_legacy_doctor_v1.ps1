param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function EnsureDir([string]$p){ if([string]::IsNullOrWhiteSpace($p)){ return }; if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Utf8NoBom(){ New-Object System.Text.UTF8Encoding($false) }
function WriteUtf8Lf([string]$path,[string]$text){ EnsureDir (Split-Path -Parent $path); $lf = ($text -replace "`r`n","`n") -replace "`r","`n"; if(-not $lf.EndsWith("`n")){ $lf += "`n" }; [IO.File]::WriteAllText($path,$lf,(Utf8NoBom)) }
function ParseGateFile([string]$path){ try { [void][ScriptBlock]::Create((Get-Content -Raw -LiteralPath $path -Encoding UTF8)) } catch { throw ("PARSE_GATE_FAIL: " + $path + "`n" + $_.Exception.Message) } }
$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
Write-Host ("BOOTSTRAP: " + $RepoRoot) -ForegroundColor Cyan
EnsureDir (Join-Path $RepoRoot "docs")
EnsureDir (Join-Path $RepoRoot "proofs\keys")
EnsureDir (Join-Path $RepoRoot "proofs\trust")
EnsureDir (Join-Path $RepoRoot "proofs\receipts")
EnsureDir (Join-Path $RepoRoot "packets\outbox")
EnsureDir (Join-Path $RepoRoot "packets\inbox")
EnsureDir (Join-Path $RepoRoot "packets\quarantine")
EnsureDir (Join-Path $RepoRoot "packets\receipts")
EnsureDir (Join-Path $RepoRoot "scripts\storage")
EnsureDir (Join-Path $RepoRoot "scripts\nfl")
$readme = Join-Path $RepoRoot "README.md"
$readmeText = ("# Legacy Doctor`n`n" +
  "Windows-first device repair + restore manager (standalone).`n`n" +
  "- Canonical Handoff v1: local pledge + NFL duplication by hash (no inter-project RPC).`n" +
  "- Packet Constitution v1 (Option A): packet_id.txt + sha256sums last.`n`n" +
  "Dev: powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\nfl\ld_nfl_commit_v1.ps1 -RepoRoot .`n")
WriteUtf8Lf $readme $readmeText
Write-Host "BOOTSTRAP_OK" -ForegroundColor Green
