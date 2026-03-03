param(
  [string]$OutPath = (Join-Path $PSScriptRoot "_clipboard_clean.ps1"),
  [switch]$AllowScriptPipelines
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Info([string]$m){ Write-Host $m -ForegroundColor DarkGray }
function Ok([string]$m){ Write-Host $m -ForegroundColor Green }
function Warn([string]$m){ Write-Host $m -ForegroundColor Yellow }
function Fail([string]$m){ Write-Host $m -ForegroundColor Red; exit 1 }

$raw = Get-Clipboard -Raw
if ([string]::IsNullOrWhiteSpace($raw)) { Fail "Clipboard was empty." }

# If the clipboard still looks like a console transcript, refuse.
$looksLikeTranscript = $false
if ($raw -match "(?m)^\s*PS(?:\s+[A-Za-z]:\\[^>]*?)?>\s*") { $looksLikeTranscript = $true }
if ($raw -match "(?m)^(WROTE OK:|PATCHED OK:|PARSE OK:|INVARIANT OK:|DOC OK:|SELFCHECK OK\.|NEXT:|ENTRYPOINT:|PS5\.1 GATE OK:|DONE\s+runDir=|FILES\s+|AUDIT\s+|HASHES\s+).*$") { $looksLikeTranscript = $true }
if ($looksLikeTranscript) {
  Fail "Clipboard looks like console transcript/output. Copy ONLY the command block you intend to run (no prompts, no outputs), then re-run safe-paste."
}

# Optionally refuse if it looks like you copied a script-writing pipeline (common loop source).
if (-not $AllowScriptPipelines) {
  if ($raw -match "(?im)\bSet-Content\b" -and $raw -match "(?im)\bScriptBlock\]::Create\b") {
    Fail "Clipboard looks like a script-writing pipeline (Set-Content + ScriptBlock::Create). That is usually a copy/paste loop. If you REALLY intend to run it, re-run with -AllowScriptPipelines."
  }
}

# Strip prompts if any slipped in (double safety)
$clean = [regex]::Replace($raw, "(?m)^\s*PS(?:\s+[A-Za-z]:\\[^>]*?)?>\s*", "")

# Drop obvious output-only lines (extra safety)
$clean = [regex]::Replace($clean, "(?m)^(WROTE OK:|PATCHED OK:|PARSE OK:|INVARIANT OK:|DOC OK:|SELFCHECK OK\.|NEXT:|ENTRYPOINT:|PS5\.1 GATE OK:|DONE\s+runDir=|DONE\s+|FILES\s+|AUDIT\s+|HASHES\s+).*$\r?\n?", "")

# Remove empty lines
$clean = [regex]::Replace($clean, "(?m)^\s*$\r?\n?", "")

if ([string]::IsNullOrWhiteSpace($clean)) { Fail "After cleaning, nothing runnable remained." }

Set-Content -LiteralPath $OutPath -Encoding UTF8 -Value $clean
Ok ("WROTE CLEAN SCRIPT: {0}" -f $OutPath)
Info "RUN IT WITH:"
Info ("  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $OutPath)
