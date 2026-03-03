param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if([string]::IsNullOrWhiteSpace($p)){ return }; if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Utf8NoBom(){ New-Object System.Text.UTF8Encoding($false) }
function WriteUtf8Lf([string]$path,[string]$text){ EnsureDir (Split-Path -Parent $path); $lf=($text -replace "`r`n","`n") -replace "`r","`n"; if(-not $lf.EndsWith("`n")){ $lf+="`n" }; [IO.File]::WriteAllText($path,$lf,(Utf8NoBom)) }
function ParseGateFile([string]$path){ try { [void][ScriptBlock]::Create((Get-Content -Raw -LiteralPath $path -Encoding UTF8)) } catch { throw ("PARSE_GATE_FAIL: " + $path + "`n" + $_.Exception.Message) } }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ScriptsDir = Join-Path $RepoRoot "scripts\storage"
EnsureDir $ScriptsDir

# Installer copies from a sibling source file to avoid brittle embedded payload quoting.
$InstallerPath = Join-Path $ScriptsDir "install_ld_storage_tool_v1.ps1"
$TargetToolPath = Join-Path $ScriptsDir "ld_storage_v1.ps1"

$I = New-Object System.Collections.Generic.List[string]
[void]$I.Add("param(")
[void]$I.Add("  [Parameter(Mandatory=$true)][string]$RepoRoot,")
[void]$I.Add("  [string]$SourceToolPath")
[void]$I.Add(")")
[void]$I.Add("$ErrorActionPreference=`"Stop`"")
[void]$I.Add("Set-StrictMode -Version Latest")
[void]$I.Add("function Die([string]$m){ throw $m }")
[void]$I.Add("function EnsureDir([string]$p){ if([string]::IsNullOrWhiteSpace($p)){ return }; if(-not (Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }")
[void]$I.Add("function Utf8NoBom(){ New-Object System.Text.UTF8Encoding($false) }")
[void]$I.Add("function WriteUtf8Lf([string]$path,[string]$text){ EnsureDir (Split-Path -Parent $path); $lf=($text -replace ``"`r`n``",``"`n``") -replace ``"`r``",``"`n``"; if(-not $lf.EndsWith(`"`n`")){ $lf+=`"`n`" }; [IO.File]::WriteAllText($path,$lf,(Utf8NoBom)) }")
[void]$I.Add("function ParseGateFile([string]$path){ try { [void][ScriptBlock]::Create((Get-Content -Raw -LiteralPath $path -Encoding UTF8)) } catch { throw (``"PARSE_GATE_FAIL: ``" + $path + ``"`n``" + $_.Exception.Message) } }")
[void]$I.Add("")
[void]$I.Add("$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path")
[void]$I.Add("$ScriptsDir = Join-Path $RepoRoot ``"scripts\storage``"")
[void]$I.Add("$Target = Join-Path $ScriptsDir ``"ld_storage_v1.ps1``"")
[void]$I.Add("EnsureDir $ScriptsDir")
[void]$I.Add("")
[void]$I.Add("if([string]::IsNullOrWhiteSpace($SourceToolPath)){")
[void]$I.Add("  $here = Split-Path -Parent $MyInvocation.MyCommand.Path")
[void]$I.Add("  $SourceToolPath = Join-Path $here ``"ld_storage_v1.ps1``"")
[void]$I.Add("}")
[void]$I.Add("if(-not (Test-Path -LiteralPath $SourceToolPath)){ Die (``"MISSING_SOURCE_TOOL: ``" + $SourceToolPath) }")
[void]$I.Add("$txt = Get-Content -Raw -LiteralPath $SourceToolPath -Encoding UTF8")
[void]$I.Add("WriteUtf8Lf $Target $txt")
[void]$I.Add("ParseGateFile $Target")
[void]$I.Add("Write-Host (``"INSTALL_OK: ``" + $Target) -ForegroundColor Green")

$installer = ($I.ToArray() -join "`n") + "`n"
WriteUtf8Lf $InstallerPath $installer
ParseGateFile $InstallerPath
Write-Host ("WROTE+PARSE_OK: " + $InstallerPath) -ForegroundColor Green

# Sanity: parse-gate the current tool too (source of truth).
if(Test-Path -LiteralPath $TargetToolPath){ ParseGateFile $TargetToolPath; Write-Host ("TOOL_PARSE_OK: " + $TargetToolPath) -ForegroundColor Green }
