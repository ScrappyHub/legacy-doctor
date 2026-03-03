param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function Utf8NoBom(){ New-Object System.Text.UTF8Encoding($false) }
function WriteUtf8Lf([string]$path,[string]$text){ $lf=($text -replace "`r`n","`n") -replace "`r","`n"; if(-not $lf.EndsWith("`n")){ $lf+="`n" }; [IO.File]::WriteAllText($path,$lf,(Utf8NoBom)) }
function ParseGateFile([string]$path){ try { [void][ScriptBlock]::Create((Get-Content -Raw -LiteralPath $path -Encoding UTF8)) } catch { throw ("PARSE_GATE_FAIL: " + $path + "`n" + $_.Exception.Message) } }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$Target = Join-Path $RepoRoot "scripts\storage\ld_storage_v1.ps1"
if(-not (Test-Path -LiteralPath $Target)){ Die ("MISSING_TARGET: " + $Target) }

$txt = Get-Content -Raw -LiteralPath $Target -Encoding UTF8

# Fix: DriveLetter is [char] in PS5.1; ToUpperInvariant() must be called on string-cast.
# Replace any "$_.DriveLetter.ToUpperInvariant()" variant (with optional spaces/parentheses) with "([string]$_.DriveLetter).ToUpperInvariant()".
$pattern = '\$\_\s*\.DriveLetter\s*\.ToUpperInvariant\s*\(\s*\)'
$repl    = '([string]$_.DriveLetter).ToUpperInvariant()'
$m = [regex]::Matches($txt, $pattern)
if($m.Count -lt 1){ Die ("PATCH_NO_MATCH: did not find pattern " + $pattern) }
$txt2 = [regex]::Replace($txt, $pattern, $repl)
if($txt2 -eq $txt){ Die "PATCH_NO_CHANGE" }

WriteUtf8Lf $Target $txt2
ParseGateFile $Target
Write-Host ("PATCH_OK: " + $Target + " replaced=" + $m.Count) -ForegroundColor Green
