param(
  [switch]$PruneStamped,
  [int]$Keep = 25
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function Info([string]$m){ Write-Host $m -ForegroundColor DarkGray }
function Ok([string]$m){ Write-Host $m -ForegroundColor Green }
function Fail([string]$m){ Write-Host $m -ForegroundColor Red; exit 1 }

$repoRoot  = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$safePaste = Join-Path $repoRoot "scripts\safe-paste.ps1"
if (-not (Test-Path -LiteralPath $safePaste)) { throw ("Missing: {0}" -f $safePaste) }

# The REAL command we want to run
$cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run.ps1"
Ok "SAFE-RUN (no clipboard)"
Info $cmd

# Run safe-paste (stamped) and capture output
$out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $safePaste -Text $cmd -StampOut 2>&1
$out | ForEach-Object { $_ } | Out-Host

# Extract stamped clean script path from: "WROTE CLEAN SCRIPT: <path>"
$m = ($out | Select-String -Pattern "^\s*WROTE CLEAN SCRIPT:\s*(.+)\s*$" -AllMatches | Select-Object -Last 1)
if (-not $m) { Fail "Could not find ""WROTE CLEAN SCRIPT:"" line in safe-paste output." }
$cleanPath = $m.Matches[0].Groups[1].Value.Trim()
if ([string]::IsNullOrWhiteSpace($cleanPath)) { Fail "Parsed clean script path was empty." }
if (-not (Test-Path -LiteralPath $cleanPath)) { Fail ("Clean script not found: {0}" -f $cleanPath) }

Ok ("RUN CLEAN SCRIPT: {0}" -f $cleanPath)
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cleanPath | Out-Host

if ($PruneStamped) {
  $dir   = Split-Path -Parent $cleanPath
  $files = Get-ChildItem -LiteralPath $dir -Filter "_clipboard_clean_*.ps1" | Sort-Object LastWriteTime -Descending
  $total = $files.Count
  $removed = 0
  Info ("Stamped clean scripts found: {0}" -f $total)
  Info ("Keep threshold: {0}" -f $Keep)
  if ($total -gt $Keep) {
    $toRemove = $files | Select-Object -Skip $Keep
    foreach ($f in $toRemove) {
      try {
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
        $removed++
      } catch {
        # best-effort; ignore
      }
    }
    Info ("Pruned stamped clean scripts. Kept newest {0}." -f $Keep)
  } else {
    Info "No prune needed."
  }
  $kept = $total - $removed
  $removedPct = 0
  $keptPct = 0
  if ($total -gt 0) {
    $removedPct = [math]::Round(($removed / [double]$total) * 100.0, 2)
    $keptPct    = [math]::Round(($kept    / [double]$total) * 100.0, 2)
  }
  Info ("Removed: {0}" -f $removed)
  Info ("RemovedPct: {0}%" -f $removedPct)
  Info ("Kept: {0}" -f $kept)
  Info ("KeptPct: {0}%" -f $keptPct)
}
