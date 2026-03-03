param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Require-File([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { throw ("Missing: {0}" -f $p) }
}

$repoRoot   = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$scriptsDir = Join-Path $repoRoot "scripts"

$doctorPath    = Join-Path $scriptsDir "doctor.ps1"
$runPath       = Join-Path $scriptsDir "run.ps1"
$gatePath      = Join-Path $scriptsDir "gate-ps51.ps1"
$pkgPath       = Join-Path $scriptsDir "engine-package.ps1"
$selfcheckPath = Join-Path $scriptsDir "selfcheck.ps1"
$entryMdPath   = Join-Path $scriptsDir "_entrypoints.md"

Require-File $doctorPath
Require-File $runPath
Require-File $gatePath
Require-File $pkgPath

# ------------------------------------------------------------
# 1) WRITE scripts\selfcheck.ps1  (StrictMode-safe)
# ------------------------------------------------------------
$lines = @()

$lines += 'param('
$lines += '  [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path'
$lines += ')'
$lines += ''
$lines += '$ErrorActionPreference = "Stop"'
$lines += 'Set-StrictMode -Version Latest'
$lines += ''
$lines += 'function Fail([string]$msg) { Write-Host $msg -ForegroundColor Red; exit 1 }'
$lines += 'function Ok([string]$msg)   { Write-Host $msg -ForegroundColor Green }'
$lines += 'function Warn([string]$msg) { Write-Host $msg -ForegroundColor Yellow }'
$lines += ''
$lines += 'function Require-File([string]$p) { if (-not (Test-Path -LiteralPath $p)) { Fail ("Missing required file: {0}" -f $p) } }'
$lines += ''
$lines += '$runPath     = Join-Path $RepoRoot "scripts\run.ps1"'
$lines += '$gatePath    = Join-Path $RepoRoot "scripts\gate-ps51.ps1"'
$lines += '$doctorPath  = Join-Path $RepoRoot "scripts\doctor.ps1"'
$lines += '$pkgPath     = Join-Path $RepoRoot "scripts\engine-package.ps1"'
$lines += '$entryMdPath = Join-Path $RepoRoot "scripts\_entrypoints.md"'
$lines += ''
$lines += 'Require-File $runPath'
$lines += 'Require-File $gatePath'
$lines += 'Require-File $doctorPath'
$lines += 'Require-File $pkgPath'
$lines += ''
$lines += 'try { [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $runPath))    | Out-Null } catch { Fail ("Parse failed: run.ps1`r`n{0}" -f $_.Exception.Message) }'
$lines += 'try { [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $gatePath))   | Out-Null } catch { Fail ("Parse failed: gate-ps51.ps1`r`n{0}" -f $_.Exception.Message) }'
$lines += 'try { [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $doctorPath)) | Out-Null } catch { Fail ("Parse failed: doctor.ps1`r`n{0}" -f $_.Exception.Message) }'
$lines += 'try { [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $pkgPath))    | Out-Null } catch { Fail ("Parse failed: engine-package.ps1`r`n{0}" -f $_.Exception.Message) }'
$lines += ''
$lines += 'Ok "PARSE OK: run.ps1 / gate-ps51.ps1 / doctor.ps1 / engine-package.ps1"'
$lines += ''
$lines += '# Invariant: doctor.ps1 must not contain gate remnants'
$lines += '$doctorRaw = Get-Content -Raw -LiteralPath $doctorPath'
$lines += 'if ($doctorRaw -match ''gate-ps51\.ps1'' -or $doctorRaw -match ''\`$gateExe'' -or $doctorRaw -match ''\`$gateScript'') {'
$lines += '  Fail "doctor.ps1 contains gate leftovers (gate-ps51.ps1 or `$gateExe/`$gateScript). Gate must run only via run.ps1."'
$lines += '}'
$lines += 'Ok "INVARIANT OK: doctor.ps1 has no gate leftovers."'
$lines += ''
$lines += '# Invariant: run.ps1 references gate + doctor'
$lines += '$runRaw = Get-Content -Raw -LiteralPath $runPath'
$lines += 'if ($runRaw -notmatch ''gate-ps51\.ps1'') { Fail "run.ps1 does not reference gate-ps51.ps1 (required)." }'
$lines += 'if ($runRaw -notmatch ''doctor\.ps1'')    { Fail "run.ps1 does not reference doctor.ps1 (required)." }'
$lines += 'Ok "INVARIANT OK: run.ps1 references gate + doctor."'
$lines += ''
$lines += 'if (Test-Path -LiteralPath $entryMdPath) { Ok "DOC OK: scripts\_entrypoints.md exists." } else { Warn "DOC WARN: scripts\_entrypoints.md missing." }'
$lines += ''
$lines += 'Write-Host "SELFCHECK OK." -ForegroundColor Green'

Set-Content -LiteralPath $selfcheckPath -Encoding UTF8 -Value ($lines -join "`r`n")
[ScriptBlock]::Create((Get-Content -Raw -LiteralPath $selfcheckPath)) | Out-Null
Write-Host ("WROTE OK: {0}" -f $selfcheckPath) -ForegroundColor Green

# ------------------------------------------------------------
# 2) WRITE scripts\_entrypoints.md
# ------------------------------------------------------------
$md = @()
$md += '# Legacy Doctor — Entry Points (PS5.1)'
$md += ''
$md += '## Canonical entrypoint (ALWAYS use this)'
$md += '```powershell'
$md += 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run.ps1'
$md += '```'
$md += ''
$md += '## Self-check'
$md += '```powershell'
$md += 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\selfcheck.ps1'
$md += '```'
$md += ''
$md += '## Components (do not run directly)'
$md += '- scripts\doctor.ps1 — orchestrator (expects entrypoint contract)'
$md += '- scripts\gate-ps51.ps1 — PS5.1 compat scan (runs via run.ps1)'
$md += '- scripts\engine-package.ps1 — packages a completed run directory'

Set-Content -LiteralPath $entryMdPath -Encoding UTF8 -Value ($md -join "`r`n")
Write-Host ("WROTE OK: {0}" -f $entryMdPath) -ForegroundColor Green

# ------------------------------------------------------------
# 3) PATCH doctor.ps1 (WARNING ONLY; suppressed by env flag)
# ------------------------------------------------------------
$marker = '# --- ENTRYPOINT CONTRACT: use-run-ps1 (warning only) ---'
$doctorRaw = Get-Content -Raw -LiteralPath $doctorPath

# remove any prior contract block (idempotent)
$doctorRaw = [regex]::Replace(
  $doctorRaw,
  '(?s)# --- ENTRYPOINT CONTRACT: use-run-ps1 \(warning only\) ---.*?\r?\n\r?\n',
  '',
  1
)

$blockLines = @()
$blockLines += '# --- ENTRYPOINT CONTRACT: use-run-ps1 (warning only) ---'
$blockLines += '# Canonical execution is scripts\run.ps1 (it runs gate once, then runs doctor).'
$blockLines += '# Running doctor.ps1 directly bypasses the deterministic entrypoint.'
$blockLines += 'try {'
$blockLines += '  if ($env:LEGACYDOCTOR_ENTRYPOINT -ne "run.ps1") {'
$blockLines += '    Write-Host "WARNING: Do not run scripts\doctor.ps1 directly. Use scripts\run.ps1." -ForegroundColor Yellow'
$blockLines += '  }'
$blockLines += '} catch {}'
$block = ($blockLines -join "`r`n") + "`r`n`r`n"

if ($doctorRaw -match [regex]::Escape($marker)) {
  Write-Host "doctor.ps1 already has entrypoint warning (no patch needed)." -ForegroundColor DarkGray
} else {
  if ($doctorRaw -match '(?m)^\s*Set-StrictMode\s+-Version\s+Latest\s*$') {
    $doctorPatched = [regex]::Replace(
      $doctorRaw,
      '(?m)^\s*Set-StrictMode\s+-Version\s+Latest\s*$',
      { param($m) $m.Value + "`r`n`r`n" + $block },
      1
    )
  } else {
    $doctorPatched = $block + $doctorRaw
  }

  Set-Content -LiteralPath $doctorPath -Encoding UTF8 -Value $doctorPatched
  [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $doctorPath)) | Out-Null
  Write-Host ("PATCHED OK: {0}" -f $doctorPath) -ForegroundColor Green
}

# ------------------------------------------------------------
# 4) PATCH run.ps1 to set env flag only for doctor invocation
# ------------------------------------------------------------
$runMarker = '# --- LEGACYDOCTOR_ENTRYPOINT FLAG (do not remove) ---'
$runRaw = Get-Content -Raw -LiteralPath $runPath

if ($runRaw -match [regex]::Escape($runMarker)) {
  Write-Host "run.ps1 already sets LEGACYDOCTOR_ENTRYPOINT (no patch needed)." -ForegroundColor DarkGray
} else {
  $setLines = @()
  $setLines += '# --- LEGACYDOCTOR_ENTRYPOINT FLAG (do not remove) ---'
  $setLines += '$env:LEGACYDOCTOR_ENTRYPOINT = "run.ps1"'
  $setBlock = ($setLines -join "`r`n") + "`r`n"

  if ($runRaw -match '(?m)^\s*&\s*powershell\.exe\b.*-File\s+\$doctor\b') {
    $runPatched = [regex]::Replace(
      $runRaw,
      '(?m)^\s*&\s*powershell\.exe\b.*-File\s+\$doctor\b.*$',
      { param($m) $setBlock + $m.Value },
      1
    )
  } else {
    $runPatched = $setBlock + "`r`n" + $runRaw
  }

  Set-Content -LiteralPath $runPath -Encoding UTF8 -Value $runPatched
  [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $runPath)) | Out-Null
  Write-Host ("PATCHED OK: {0}" -f $runPath) -ForegroundColor Green
}

# ------------------------------------------------------------
# 5) RUN selfcheck
# ------------------------------------------------------------
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $selfcheckPath | Out-Host
Write-Host "NEXT: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run.ps1" -ForegroundColor DarkGray
