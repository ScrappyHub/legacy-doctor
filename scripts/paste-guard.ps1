param(
  [string]$OutPath = (Join-Path $PSScriptRoot "_clipboard_clean.ps1")
)

$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest

function Info([string]$m){ Write-Host $m -ForegroundColor DarkGray }
function Ok([string]$m){ Write-Host $m -ForegroundColor Green }
function Warn([string]$m){ Write-Host $m -ForegroundColor Yellow }
function Fail([string]$m){ Write-Host $m -ForegroundColor Red; exit 1 }

$raw = Get-Clipboard -Raw
if ([string]::IsNullOrWhiteSpace($raw)) { Fail "Clipboard was empty." }

# Strip prompts like:
#   PS C:\path> command
#   PS> command
$clean = [regex]::Replace($raw, "(?m)^\s*PS(?:\s+[A-Za-z]:\\[^>]*?)?>\s*", "")

# Drop obvious output-only lines that people accidentally re-run.
# (conservative; only lines that begin with these tokens)
$clean = [regex]::Replace($clean, "(?m)^(PATCHED OK:|WROTE OK:|PARSE OK:|INVARIANT OK:|DOC OK:|SELFCHECK OK\.|NEXT:|ENTRYPOINT:|PS5\.1 GATE OK:|DONE\s+runDir=|DONE\s+|FILES\s+|AUDIT\s+|HASHES\s+).*$\r?\n?", "")

# Remove empty lines
$clean = [regex]::Replace($clean, "(?m)^\s*$\r?\n?", "")

if ([string]::IsNullOrWhiteSpace($clean)) {
  Fail "After stripping prompts/output, nothing runnable remained."
}

Set-Content -LiteralPath $OutPath -Encoding UTF8 -Value $clean
Ok ("WROTE CLEAN SCRIPT: {0}" -f $OutPath)
Info "RUN IT WITH:"
Info ("  powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"{0}`"" -f $OutPath)
