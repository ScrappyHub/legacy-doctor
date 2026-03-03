param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Require-File([string]$p) {
  if (-not (Test-Path -LiteralPath $p)) { throw ("Missing: {0}" -f $p) }
}

$repoRoot   = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$scriptsDir = Join-Path $repoRoot "scripts"

$runPath      = Join-Path $scriptsDir "run.ps1"
$selfcheckPath = Join-Path $scriptsDir "selfcheck.ps1"

Require-File $runPath
Require-File $selfcheckPath

$runRaw = Get-Content -Raw -LiteralPath $runPath

# If already scoped, do nothing
if ($runRaw -match '\$__prev\s*=\s*\$env:LEGACYDOCTOR_ENTRYPOINT' -and $runRaw -match 'finally\s*\{\s*(.|\r|\n)*LEGACYDOCTOR_ENTRYPOINT') {
  Write-Host "run.ps1 already scopes LEGACYDOCTOR_ENTRYPOINT (no patch needed)." -ForegroundColor DarkGray
}
else {

  # Remove any existing simple flag block we previously inserted
  $runRaw = [regex]::Replace(
    $runRaw,
    '(?s)# --- LEGACYDOCTOR_ENTRYPOINT FLAG \(do not remove\) ---\s*\r?\n\$env:LEGACYDOCTOR_ENTRYPOINT\s*=\s*"run\.ps1"\s*\r?\n',
    '',
    1
  )

  # Replace the doctor invocation line with a scoped block.
  # We target the FIRST line that invokes powershell.exe -File $doctor ... and replace it.
  $pattern = '(?m)^\s*&\s*powershell\.exe\b.*-NoProfile\b.*-ExecutionPolicy\s+Bypass\b.*-File\s+\$doctor\b.*$'

  if ($runRaw -notmatch $pattern) {
    throw "run.ps1: could not find the doctor invocation line to patch. (Expected a line invoking: powershell.exe ... -File `$doctor ...)"
  }

  $scoped = @()
  $scoped += '# --- LEGACYDOCTOR_ENTRYPOINT FLAG (scoped; do not remove) ---'
  $scoped += '$__prev = $env:LEGACYDOCTOR_ENTRYPOINT'
  $scoped += 'try {'
  $scoped += '  $env:LEGACYDOCTOR_ENTRYPOINT = "run.ps1"'
  $scoped += '  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $doctor @DoctorArgs | Out-Host'
  $scoped += '}'
  $scoped += 'finally {'
  $scoped += '  if ($null -eq $__prev) { Remove-Item Env:\LEGACYDOCTOR_ENTRYPOINT -ErrorAction SilentlyContinue }'
  $scoped += '  else { $env:LEGACYDOCTOR_ENTRYPOINT = $__prev }'
  $scoped += '}'
  $scopedBlock = ($scoped -join "`r`n")

  $runPatched = [regex]::Replace(
    $runRaw,
    $pattern,
    { param($m) $scopedBlock },
    1
  )

  Set-Content -LiteralPath $runPath -Encoding UTF8 -Value $runPatched
  [ScriptBlock]::Create((Get-Content -Raw -LiteralPath $runPath)) | Out-Null
  Write-Host ("PATCHED OK: {0}" -f $runPath) -ForegroundColor Green
}

# Run selfcheck to ensure invariants still hold
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $selfcheckPath | Out-Host
Write-Host "NEXT: powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run.ps1" -ForegroundColor DarkGray
