param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$libDir   = Join-Path $repoRoot "lib"
New-Item -ItemType Directory -Force -Path $libDir | Out-Null

$commonPath = Join-Path $libDir "doctor-common.ps1"

$lines = @(
  '$ErrorActionPreference = "Stop"',
  'Set-StrictMode -Version Latest',
  '',
  'function New-RunId {',
  '  param([string]$Prefix = "LD")',
  '',
  '  $ts = Get-Date -Format "yyyyMMdd_HHmmss"',
  '',
  '  # PS5.1-safe host name fallback (NO ?? operator)',
  '  $hostShort = $env:COMPUTERNAME',
  '  if ([string]::IsNullOrWhiteSpace($hostShort)) { $hostShort = "HOST" }',
  '',
  '  $rand = ([Guid]::NewGuid().ToString("N").Substring(0,4)).ToUpperInvariant()',
  '  return "{0}_{1}_{2}_{3}" -f $Prefix, $ts, $hostShort, $rand',
  '}',
  '',
  'function Ensure-Dir {',
  '  param([Parameter(Mandatory=$true)][string]$Path)',
  '  New-Item -ItemType Directory -Force -Path $Path | Out-Null',
  '  return (Resolve-Path -LiteralPath $Path).Path',
  '}',
  '',
  'function Write-Json {',
  '  param(',
  '    [Parameter(Mandatory=$true)][object]$Obj,',
  '    [Parameter(Mandatory=$true)][string]$Path',
  '  )',
  '  $json = $Obj | ConvertTo-Json -Depth 50',
  '  Set-Content -LiteralPath $Path -Encoding UTF8 -Value $json',
  '}',
  '',
  'function Audit-Append {',
  '  param(',
  '    [Parameter(Mandatory=$true)][string]$RunDir,',
  '    [Parameter(Mandatory=$true)][string]$Engine,',
  '    [Parameter(Mandatory=$true)][string]$EventType,',
  '    [string]$Action,',
  '    [string]$Subject,',
  '    [string]$Result = "ok",',
  '    [hashtable]$Details',
  '  )',
  '  $auditPath = Join-Path $RunDir "audit.v1.jsonl"',
  '  $o = [ordered]@{',
  '    ts         = ([DateTime]::UtcNow.ToString("o"))',
  '    engine     = $Engine',
  '    event_type = $EventType',
  '    action     = $Action',
  '    subject    = $Subject',
  '    result     = $Result',
  '    details    = $Details',
  '  }',
  '  $line = ($o | ConvertTo-Json -Depth 30 -Compress)',
  '  Add-Content -LiteralPath $auditPath -Encoding UTF8 -Value $line',
  '}',
  '',
  'function Get-Sha256 {',
  '  param([Parameter(Mandatory=$true)][string]$Path)',
  '  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()',
  '}',
  '',
  'function Seal-Run {',
  '  param([Parameter(Mandatory=$true)][string]$RunDir)',
  '',
  '  $hashOut = Join-Path $RunDir "sha256sums.txt"',
  '  if (Test-Path -LiteralPath $hashOut) { Remove-Item -LiteralPath $hashOut -Force }',
  '',
  '  $paths = New-Object System.Collections.Generic.List[string]',
  '  $paths.Add((Join-Path $RunDir "manifest.v1.json"))',
  '  $paths.Add((Join-Path $RunDir "entitlements.v1.json"))',
  '  $paths.Add((Join-Path $RunDir "audit.v1.jsonl"))',
  '',
  '  $artDir = Join-Path $RunDir "artifacts"',
  '  if (Test-Path -LiteralPath $artDir) {',
  '    Get-ChildItem -LiteralPath $artDir -File -Recurse | ForEach-Object { $paths.Add($_.FullName) }',
  '  }',
  '',
  '  foreach ($p in $paths) {',
  '    if (-not (Test-Path -LiteralPath $p)) { continue }',
  '    $h = Get-Sha256 -Path $p',
  '    $rel = $p.Substring($RunDir.Length).TrimStart("\","/")',
  '    Add-Content -LiteralPath $hashOut -Encoding UTF8 -Value ("{0}  {1}" -f $h, $rel)',
  '  }',
  '',
  '  Audit-Append -RunDir $RunDir -Engine "orchestrator" -EventType "RUN_SEALED" -Action "seal" -Subject $hashOut -Details @{ file="sha256sums.txt" }',
  '}'
)

Set-Content -LiteralPath $commonPath -Encoding UTF8 -Value $lines

# Hard fail if ?? exists (should never happen on PS5.1 baseline)
$raw = Get-Content -Raw -LiteralPath $commonPath
if ($raw -match "\?\?") { throw "repair failed: found ?? in $commonPath" }

# Parse check (audit) — DO NOT print success unless this passes
[ScriptBlock]::Create($raw) | Out-Null

Write-Host ("REPAIRED OK: {0}" -f $commonPath) -ForegroundColor Green
