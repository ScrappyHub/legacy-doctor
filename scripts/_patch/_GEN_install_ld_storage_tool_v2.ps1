param([Parameter(Mandatory=$true)][string]$RepoRoot)
$ErrorActionPreference="Stop"
Set-StrictMode -Version Latest
function Die([string]$m){ throw $m }
function EnsureDir([string]$p){ if([string]::IsNullOrWhiteSpace($p)){return}; if(-not(Test-Path -LiteralPath $p)){ New-Item -ItemType Directory -Force -Path $p | Out-Null } }
function Utf8NoBom(){ New-Object System.Text.UTF8Encoding($false) }
function WriteUtf8Lf([string]$path,[string]$text){ EnsureDir (Split-Path -Parent $path); $lf=($text -replace "`r`n","`n") -replace "`r","`n"; if(-not $lf.EndsWith("`n")){ $lf+="`n" }; [IO.File]::WriteAllText($path,$lf,(Utf8NoBom)) }
function ParseGateFile([string]$path){ try { [void][ScriptBlock]::Create((Get-Content -Raw -LiteralPath $path -Encoding UTF8)) } catch { throw ("PARSE_GATE_FAIL: " + $path + "`n" + $_.Exception.Message) } }

$RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
$ToolPath = Join-Path $RepoRoot "scripts\storage\ld_storage_v1.ps1"
if(-not (Test-Path -LiteralPath $ToolPath)){ Die ("MISSING_TOOL_TARGET: " + $ToolPath) }
$ToolText = Get-Content -Raw -LiteralPath $ToolPath -Encoding UTF8

# Normalize to LF and remove exactly one trailing LF so Split does not produce a trailing empty element.
$norm = ($ToolText -replace "`r`n","`n") -replace "`r","`n"
if($norm.EndsWith("`n")){ $norm = $norm.Substring(0, $norm.Length - 1) }
$lines = $norm.Split("`n")

$OutPath = Join-Path $RepoRoot "scripts\_patch\_PATCH_install_ld_storage_v1_tool_v2.ps1"
$P = New-Object System.Collections.Generic.List[string]
[void]$P.Add("param([Parameter(Mandatory=`$true)][string]`$RepoRoot)")
[void]$P.Add("`$ErrorActionPreference=`"Stop`"")
[void]$P.Add("Set-StrictMode -Version Latest")
[void]$P.Add("function Die([string]`$m){ throw `$m }")
[void]$P.Add("function EnsureDir([string]`$p){ if([string]::IsNullOrWhiteSpace(`$p)){return}; if(-not(Test-Path -LiteralPath `$p)){ New-Item -ItemType Directory -Force -Path `$p | Out-Null } }")
[void]$P.Add("function Utf8NoBom(){ New-Object System.Text.UTF8Encoding(`$false) }")
[void]$P.Add("function WriteUtf8Lf([string]`$path,[string]`$text){ EnsureDir (Split-Path -Parent `$path); `$lf=(`$text -replace ``"`r`n``",``"`n``") -replace ``"`r``",``"`n``"; if(-not `$lf.EndsWith(`"`n`")){ `$lf+=`"`n`" }; [IO.File]::WriteAllText(`$path,`$lf,(Utf8NoBom)) }")
[void]$P.Add("function ParseGateFile([string]`$path){ try { [void][ScriptBlock]::Create((Get-Content -Raw -LiteralPath `$path -Encoding UTF8)) } catch { throw (``"PARSE_GATE_FAIL: ``" + `$path + ``"`n``" + `$_ .Exception.Message) } }")
[void]$P.Add("")
[void]$P.Add("`$RepoRoot = (Resolve-Path -LiteralPath `$RepoRoot).Path")
[void]$P.Add("`$Target = Join-Path `$RepoRoot ``"scripts\storage\ld_storage_v1.ps1``"")
[void]$P.Add("EnsureDir (Split-Path -Parent `$Target)")
[void]$P.Add("")
[void]$P.Add("# Embedded tool payload (UTF-8 no BOM, LF) — newline-separated array (NO commas).")
[void]$P.Add("`$tool = @(")
foreach($ln in @($lines)){
  $safe = $ln.Replace("'","''")
  [void]$P.Add(("  '" + $safe + "'"))
}
[void]$P.Add(") -join ``"`n``"")
[void]$P.Add("if(-not `$tool.EndsWith(`"`n`")){ `$tool += `"`n`" }")
[void]$P.Add("WriteUtf8Lf `$Target `$tool")
[void]$P.Add("ParseGateFile `$Target")
[void]$P.Add("Write-Host (``"PATCH_OK: installed+parse-gated ``" + `$Target) -ForegroundColor Green")

$out = ($P.ToArray() -join "`n") + "`n"
WriteUtf8Lf $OutPath $out
ParseGateFile $OutPath
Write-Host ("WROTE+PARSE_OK: " + $OutPath) -ForegroundColor Green
