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

# DriveLetter is [char] in PS5.1. We must cast the *DriveLetter value* to string before ToUpperInvariant().
$repl = '([string]$_.DriveLetter).ToUpperInvariant()'

# Variant A: $_.DriveLetter.ToUpperInvariant()
$patA = '\$_\s*\.DriveLetter\s*\.ToUpperInvariant\s*\(\s*\)'
$mA = [regex]::Matches($txt, $patA)

# Variant B: [string]$_.DriveLetter.ToUpperInvariant()  (still calls ToUpperInvariant on char)
$patB = '\[string\]\s*\$_\s*\.DriveLetter\s*\.ToUpperInvariant\s*\(\s*\)'
$mB = [regex]::Matches($txt, $patB)

if(($mA.Count + $mB.Count) -lt 1){ Die ("PATCH_NO_MATCH: neither variant found. patA=" + $patA + " patB=" + $patB) }

$txt2 = $txt
if($mB.Count -gt 0){ $txt2 = [regex]::Replace($txt2, $patB, $repl) }
if($mA.Count -gt 0){ $txt2 = [regex]::Replace($txt2, $patA, $repl) }

if($txt2 -eq $txt){ Die "PATCH_NO_CHANGE" }
WriteUtf8Lf $Target $txt2
ParseGateFile $Target
Write-Host ("PATCH_OK: " + $Target + " replacedA=" + $mA.Count + " replacedB=" + $mB.Count) -ForegroundColor Green
