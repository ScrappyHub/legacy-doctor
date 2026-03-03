param([Parameter(Mandatory=$true)][string]$Root)
Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function WriteUtf8NoBom([string]$Path,[string]$Text){
  $dir = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path,$Text,$enc)
}

function ParseCheck([string]$Path){ [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $Path)) | Out-Null }

$out = Join-Path $Root "scripts\pipeline_score.ps1"

# Single-quoted here-string: NO interpolation, NO escaping hell.
$scorer = @' 
param(
  [Parameter(Mandatory=$true)][string]$Root,
  [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function ReadAll([string]$p){ if (-not (Test-Path -LiteralPath $p)) { return "" }; (Get-Content -Raw -LiteralPath $p) }
function Sha256([string]$p){ if (-not (Test-Path -LiteralPath $p)) { return "" }; (Get-FileHash -Algorithm SHA256 -LiteralPath $p).Hash }
function Has([string]$text,[string]$pattern){ if ([string]::IsNullOrEmpty($text)) { return $false }; [regex]::IsMatch($text,$pattern) }
function AddCheck([ref]$checks,[int]$id,[string]$name,[bool]$pass,[string]$detail){ $checks.Value += [pscustomobject]@{id=$id;name=$name;pass=$pass;detail=$detail} }

$scripts   = Join-Path $Root "scripts"
$safeRun   = Join-Path $scripts "safe-run.ps1"
$safePaste = Join-Path $scripts "safe-paste.ps1"
$tRun      = ReadAll $safeRun
$tPaste    = ReadAll $safePaste

# --- regex library (DOUBLE QUOTES: quote-safe) ---
$rxStrictMode   = "(?m)^\s*Set-StrictMode\s+-Version\s+Latest\s*$"
$rxGetClipboard = "(?im)\bGet-Clipboard\b"
$rxTextParam    = "(?im)-File\s+\$safePaste\b[\s\S]*-Text\s+\$[A-Za-z_][A-Za-z0-9_]*"
$rxStampOut     = "(?im)\b-StampOut\b"
$rxObs1         = "(?im)Stamped clean scripts found:\s*\d+"
$rxObs2         = "(?im)Keep threshold:\s*\d+"
$rxObs3         = "(?im)No prune needed\."
$rxRemovedLines = "(?im)Removed:\s*\d+[\s\S]*RemovedPct:\s*[\d.]+%[\s\S]*KeptPct:\s*[\d.]+%"
$rxTryCatchRm   = "(?im)try\s*\{[\s\S]*Remove-Item[\s\S]*\}\s*catch\s*\{"
$rxPidTokens    = "(?im)\$(pid|procid)\b"

Write-Host "PIPELINE SCORE — Legacy Doctor PowerShell Harness"
Write-Host ("Root: {0}" -f $Root)
Write-Host ("safe-run.ps1  sha256: {0}" -f (Sha256 $safeRun))
Write-Host ("safe-paste.ps1 sha256: {0}" -f (Sha256 $safePaste))

$checks = @()

AddCheck ([ref]$checks) 1  "safe-run exists"   (Test-Path -LiteralPath $safeRun)   "scripts\safe-run.ps1 present"
AddCheck ([ref]$checks) 2  "safe-paste exists" (Test-Path -LiteralPath $safePaste) "scripts\safe-paste.ps1 present"
AddCheck ([ref]$checks) 3  "StrictMode enabled (safe-run)" (Has $tRun $rxStrictMode) "safe-run sets StrictMode Latest"
AddCheck ([ref]$checks) 4  "No clipboard usage (safe-run)" (-not (Has $tRun $rxGetClipboard)) "safe-run does not call Get-Clipboard"
AddCheck ([ref]$checks) 5  "safe-run calls safe-paste with -Text" (Has $tRun $rxTextParam) "safe-run passes -Text <var> to safe-paste"
AddCheck ([ref]$checks) 6  "safe-run uses -StampOut" (Has $tRun $rxStampOut) "safe-run requests stamped clean scripts"
AddCheck ([ref]$checks) 7  "Prune observability present" ((Has $tRun $rxObs1) -and (Has $tRun $rxObs2) -and (Has $tRun $rxObs3)) "counts + no-prune branch visible"
AddCheck ([ref]$checks) 8  "Prune removed/kept % present" (Has $tRun $rxRemovedLines) "removed/kept counts + %s printed"
AddCheck ([ref]$checks) 9  "Try/Catch around Remove-Item" (Has $tRun $rxTryCatchRm) "best-effort prune delete protected"
AddCheck ([ref]$checks) 10 "safe-paste StrictMode enabled" (Has $tPaste $rxStrictMode) "safe-paste sets StrictMode Latest"
AddCheck ([ref]$checks) 11 "No $pid/$procId tokens (avoid $PID collision class)" (-not (Has $tPaste $rxPidTokens)) "no $pid/$procId tokens in safe-paste"

$total  = $checks.Count
$passed = @($checks | Where-Object { $_.pass }).Count
$pct = 0
if ($total -gt 0) { $pct = [math]::Round(($passed / [double]$total) * 100.0, 2) }

Write-Host ""
Write-Host ("CANONICAL HARNESS PERCENT: {0}% ({1}/{2})" -f $pct, $passed, $total) -ForegroundColor Cyan
Write-Host ""
foreach ($c in $checks) {
  $mark = if ($c.pass) { "[PASS]" } else { "[FAIL]" }
  Write-Host ("{0} #{1} {2} — {3}" -f $mark, $c.id, $c.name, $c.detail)
}

if ($EmitJson) {
  $obj = [pscustomobject]@{ root=$Root; percent=$pct; passed=$passed; total=$total; checks=$checks }
  $json = $obj | ConvertTo-Json -Depth 6
  Write-Host ""
  Write-Host $json
}
'@

WriteUtf8NoBom $out $scorer
ParseCheck $out
Write-Host ("WROTE OK: {0}" -f $out) -ForegroundColor Green