param(
  [Parameter(Mandatory=$true)][string]$InPath,
  [Parameter(Mandatory=$true)][string]$OutPath
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if (-not (Test-Path -LiteralPath $InPath)) { throw "Missing InPath: $InPath" }

$raw = Get-Content -Raw -LiteralPath $InPath

# Remove leading prompts like:
# "PS C:\dev\legacy-doctor> "  OR  "PS> "
# Keep only the command text after "> "
$clean = [regex]::Replace(
  $raw,
  "(?m)^\s*PS(?:\s+[A-Za-z]:\\[^>]*?)?>\s*",
  ""
)

# Also remove lines that are *only* a prompt with no command
$clean = [regex]::Replace($clean, "(?m)^\s*PS(?:\s+[A-Za-z]:\\[^>]*?)?>\s*$\r?\n?", "")

Set-Content -LiteralPath $OutPath -Encoding UTF8 -Value $clean
Write-Host ("STRIPPED OK:`n  in : {0}`n  out: {1}" -f $InPath, $OutPath) -ForegroundColor Green
