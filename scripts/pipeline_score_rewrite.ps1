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

$Scripts = Join-Path $Root "scripts"
$Writer  = Join-Path $Scripts "_write_pipeline_score.ps1"
$Out     = Join-Path $Scripts "pipeline_score.ps1"
New-Item -ItemType Directory -Force -Path $Scripts | Out-Null

# ----------------------------
# Build WRITER via $W += lines
# ----------------------------
$W = @()
$W += 'param([Parameter(Mandatory=$true)][string]$Root)'
$W += 'Set-StrictMode -Version Latest'
$W += '$ErrorActionPreference="Stop"'
$W += ''
$W += '$out = Join-Path $Root "scripts\pipeline_score.ps1"'
$W += ''
$W += '$L = @()'
$W += ''
$W += '$L += "param([Parameter(Mandatory=$true)][string]`$Root,[switch]`$EmitJson)"'
$W += '$L += "Set-StrictMode -Version Latest"'
$W += '$L += "`$ErrorActionPreference=`"Stop`""'
$W += '$L += ""'
$W += '$L += "function ReadAll([string]`$p){ if(-not(Test-Path -LiteralPath `$p)){ return `"`" }; (Get-Content -Raw -LiteralPath `$p) }"'
$W += '$L += "function Sha256([string]`$p){ if(-not(Test-Path -LiteralPath `$p)){ return `"`" }; (Get-FileHash -Algorithm SHA256 -LiteralPath `$p).Hash }"'
$W += '$L += "function Has([string]`$text,[string]`$pattern){ if([string]::IsNullOrEmpty(`$text)){ return `$false }; [regex]::IsMatch(`$text,`$pattern) }"'
$W += '$L += "function AddCheck([ref]`$checks,[int]`$id,[string]`$name,[bool]`$pass,[string]`$detail){ `$checks.Value += [pscustomobject]@{id=`$id;name=`$name;pass=`$pass;detail=`$detail} }"'
$W += '$L += ""'
$W += '$L += "`$scripts   = Join-Path `$Root `"`"scripts`"`""'
$W += '$L += "`$safeRun   = Join-Path `$scripts `"`"safe-run.ps1`"`""'
$W += '$L += "`$safePaste = Join-Path `$scripts `"`"safe-paste.ps1`"`""'
$W += '$L += "`$tRun      = ReadAll `$safeRun"'
$W += '$L += "`$tPaste    = ReadAll `$safePaste"'
$W += '$L += ""'
$W += '$L += "# --- regex library (double-quoted to avoid quote footguns) ---"'
$W += '$L += "`$rxStrictMode   = `"`"(?m)^\s*Set-StrictMode\s+-Version\s+Latest\s*$`"`""'
$W += '$L += "`$rxGetClipboard = `"`"(?im)\bGet-Clipboard\b`"`""'
$W += '$L += "`$rxTextParam    = `"`"(?im)-File\s+\$safePaste\b[\s\S]*-Text\s+\$[A-Za-z_][A-Za-z0-9_]*`"`""'
$W += '$L += "`$rxStampOut     = `"`"(?im)\b-StampOut\b`"`""'
$W += '$L += "`$rxObs1         = `"`"(?im)Stamped clean scripts found:\s*\d+`"`""'
$W += '$L += "`$rxObs2         = `"`"(?im)Keep threshold:\s*\d+`"`""'
$W += '$L += "`$rxObs3         = `"`"(?im)No prune needed\.`"`""'
$W += '$L += "`$rxRemovedLines = `"`"(?im)Removed:\s*\d+[\s\S]*RemovedPct:\s*[\d.]+%[\s\S]*KeptPct:\s*[\d.]+%`"`""'
$W += '$L += "`$rxTryCatchRm   = `"`"(?im)try\s*\{[\s\S]*Remove-Item[\s\S]*\}\s*catch\s*\{`"`""'
$W += '$L += "`$rxPidTokens    = `"`"(?im)\$(pid|procid)\b`"`""'
$W += '$L += ""'
$W += '$L += "Write-Host `"`"PIPELINE SCORE — Legacy Doctor PowerShell Harness`"`""'
$W += '$L += "Write-Host (`"`"Root: {0}`"`" -f `$Root)"'
$W += '$L += "Write-Host (`"`"safe-run.ps1  sha256: {0}`"`" -f (Sha256 `$safeRun))"'
$W += '$L += "Write-Host (`"`"safe-paste.ps1 sha256: {0}`"`" -f (Sha256 `$safePaste))"'
$W += '$L += ""'
$W += '$L += "`$checks = @()"'
$W += '$L += ""'
$W += '$L += "AddCheck ([ref]`$checks) 1  `"`"safe-run exists`"`"   (Test-Path -LiteralPath `$safeRun)   `"`"scripts\safe-run.ps1 present`"`""'
$W += '$L += "AddCheck ([ref]`$checks) 2  `"`"safe-paste exists`"`" (Test-Path -LiteralPath `$safePaste) `"`"scripts\safe-paste.ps1 present`"`""'
$W += '$L += "AddCheck ([ref]`$checks) 3  `"`"StrictMode enabled (safe-run)`"`" (Has `$tRun `$rxStrictMode) `"`"safe-run sets StrictMode Latest`"`""'
$W += '$L += "AddCheck ([ref]`$checks) 4  `"`"No clipboard usage (safe-run)`"`" (-not (Has `$tRun `$rxGetClipboard)) `"`"safe-run does not call Get-Clipboard`"`""'
$W += '$L += "AddCheck ([ref]`$checks) 5  `"`"safe-run calls safe-paste with -Text`"`" (Has `$tRun `$rxTextParam) `"`"safe-run passes -Text <var> to safe-paste`"`""'
$W += '$L += "AddCheck ([ref]`$checks) 6  `"`"safe-run uses -StampOut`"`" (Has `$tRun `$rxStampOut) `"`"safe-run requests stamped clean scripts`"`""'
$W += '$L += "AddCheck ([ref]`$checks) 7  `"`"Prune observability present`"`" ((Has `$tRun `$rxObs1) -and (Has `$tRun `$rxObs2) -and (Has `$tRun `$rxObs3)) `"`"counts + no-prune branch visible`"`""'
$W += '$L += "AddCheck ([ref]`$checks) 8  `"`"Prune removed/kept % present`"`" (Has `$tRun `$rxRemovedLines) `"`"removed/kept counts + %s printed`"`""'
$W += '$L += "AddCheck ([ref]`$checks) 9  `"`"Try/Catch around Remove-Item`"`" (Has `$tRun `$rxTryCatchRm) `"`"best-effort prune delete protected`"`""'
$W += '$L += "AddCheck ([ref]`$checks) 10 `"`"safe-paste StrictMode enabled`"`" (Has `$tPaste `$rxStrictMode) `"`"safe-paste sets StrictMode Latest`"`""'
$W += '$L += "AddCheck ([ref]`$checks) 11 `"`"No `$pid/`$procId tokens (avoid `$PID collision class)`"`" (-not (Has `$tPaste `$rxPidTokens)) `"`"no `$pid/`$procId tokens in safe-paste`"`""'
$W += '$L += ""'
$W += '$L += "`$total=`$checks.Count; `$passed=@(`$checks | Where-Object { `$_.pass }).Count; `$pct=0; if(`$total -gt 0){ `$pct=[math]::Round((`$passed/[double]`$total)*100.0,2) }"'
$W += '$L += ""'
$W += '$L += "Write-Host `"`"`"`""'
$W += '$L += "Write-Host (`"`"CANONICAL HARNESS PERCENT: {0}% ({1}/{2})`"`" -f `$pct, `$passed, `$total) -ForegroundColor Cyan"'
$W += '$L += "Write-Host `"`"`"`""'
$W += '$L += "foreach(`$c in `$checks){ `$mark=if(`$c.pass){`"`"[PASS]`"`"}else{`"`"[FAIL]`"`"}; Write-Host (`"`"{0} #{1} {2} — {3}`"`" -f `$mark, `$c.id, `$c.name, `$c.detail) }"'
$W += '$L += ""'
$W += '$L += "if(`$EmitJson){ `$obj=[pscustomobject]@{ root=`$Root; percent=`$pct; passed=`$passed; total=`$total; checks=`$checks }; `$json=`$obj | ConvertTo-Json -Depth 6; Write-Host `"`"`"`""; Write-Host `$json }"'
$W += ''
$W += '$enc = New-Object System.Text.UTF8Encoding($false)'
$W += '[System.IO.File]::WriteAllText($out, ($L -join "`r`n"), $enc)'
$W += '[ScriptBlock]::Create((Get-Content -Raw -LiteralPath $out)) | Out-Null'
$W += 'Write-Host ("WROTE OK: {0}" -f $out) -ForegroundColor Green'

# --- write WRITER (no BOM), parse-check, run deterministically ---
WriteUtf8NoBom $Writer ($W -join "`r`n")
ParseCheck $Writer
Write-Host ("WRITER PARSE OK: {0}" -f $Writer) -ForegroundColor Green
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Writer -Root $Root

# --- parse-check scorer + run scorer ---
ParseCheck $Out
Write-Host ("SCORER PARSE OK: {0}" -f $Out) -ForegroundColor Green
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Out -Root $Root