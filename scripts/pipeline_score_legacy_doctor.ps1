param(
  [Parameter(Mandatory=$true)][string]$Root,
  [switch]$EmitJson
)

Set-StrictMode -Version Latest
$ErrorActionPreference="Stop"

function ReadAll([string]$p){ if (-not (Test-Path -LiteralPath $p)) { return "" }; (Get-Content -Raw -LiteralPath $p) }
function Has([string]$text,[string]$pattern){ if ([string]::IsNullOrEmpty($text)) { return $false }; [regex]::IsMatch($text,$pattern) }
function Exists([string]$p){ Test-Path -LiteralPath $p }
function AddCheck([ref]$checks,[int]$id,[string]$area,[string]$name,[int]$weight,[bool]$pass,[string]$detail){
  $checks.Value += [pscustomobject]@{ id=$id; area=$area; name=$name; weight=$weight; pass=$pass; detail=$detail }
}

# ----------------------------
# Paths
# ----------------------------
$scripts = Join-Path $Root "scripts"
$srcRoot = Join-Path $Root "src"
$pkgRoot = Join-Path $srcRoot "legacy_doctor"

$scoreHarness = Join-Path $scripts "pipeline_score.ps1"
$safeRun      = Join-Path $scripts "safe-run.ps1"
$safePaste    = Join-Path $scripts "safe-paste.ps1"

# Core python modules you showed as untracked (so: expected target surfaces)
$pyArtifacts  = Join-Path $pkgRoot "core\artifacts.py"
$pyCrypto     = Join-Path $pkgRoot "core\crypto_bundle.py"
$pyKeys       = Join-Path $pkgRoot "core\keys.py"
$pyPaths      = Join-Path $pkgRoot "core\paths.py"
$pyPowerShell = Join-Path $pkgRoot "core\powershell.py"
$pyWinProbe   = Join-Path $pkgRoot "core\winprobe.py"
$pyDoctor     = Join-Path $pkgRoot "core\doctor.py"
$pyEngDoctor  = Join-Path $pkgRoot "core\doctor_engine.py"
$pyEngImage   = Join-Path $pkgRoot "core\image_engine.py"
$pyEngVerify  = Join-Path $pkgRoot "core\verify_engine.py"
$pyEngRepair  = Join-Path $pkgRoot "core\repair_engine.py"
$pyEngWipe    = Join-Path $pkgRoot "core\wipe_engine.py"
$pyEngExport  = Join-Path $pkgRoot "core\export_engine.py"
$pyEngLibrary = Join-Path $pkgRoot "core\library_engine.py"
$pyEject      = Join-Path $pkgRoot "core\eject.py"

$apiServer    = Join-Path $pkgRoot "api\server.py"
$apiRoutes    = Join-Path $pkgRoot "api\routes.py"

$pyproject    = Join-Path $Root "pyproject.toml"
$readme       = Join-Path $Root "README.md"
$license      = Join-Path $Root "LICENSE"
$runPs1       = Join-Path $Root "run.ps1"

# Optional-but-canonical docs (you can add later; score will reflect)
$docsDir      = Join-Path $Root "docs"
$specDoc      = Join-Path $docsDir "spec.md"
$artifactDoc  = Join-Path $docsDir "artifact-format-v1.md"
$threatDoc    = Join-Path $docsDir "threat-model.md"
$opsDoc       = Join-Path $docsDir "ops.md"
$licenseDoc   = Join-Path $docsDir "licensing.md"

# ----------------------------
# Read some text
# ----------------------------
$tPyproject = ReadAll $pyproject
$tReadme    = ReadAll $readme
$tApiServer = ReadAll $apiServer
$tApiRoutes = ReadAll $apiRoutes
$tArtifacts = ReadAll $pyArtifacts
$tCrypto    = ReadAll $pyCrypto
$tKeys      = ReadAll $pyKeys
$tEngImage  = ReadAll $pyEngImage
$tEngLib    = ReadAll $pyEngLibrary
$tEngVerify = ReadAll $pyEngVerify
$tEngRepair = ReadAll $pyEngRepair
$tEngWipe   = ReadAll $pyEngWipe

# ----------------------------
# Heuristics / regexes (lightweight, evidence-based)
# ----------------------------
$rxFastApi     = '(?im)\bfastapi\b'
$rxUvicorn     = '(?im)\buvicorn\b'
$rxPydantic    = '(?im)\bpydantic\b'
$rxTomlName    = '(?im)^\s*name\s*=\s*["'']legacy[-_]?doctor["'']\s*$'
$rxVersion     = '(?im)^\s*version\s*=\s*["''][0-9]+\.[0-9]+\.[0-9]+["'']\s*$'
$rxDeps        = '(?is)\[project\][\s\S]*\bdependencies\b'
$rxCliEntry    = '(?is)\[project\.scripts\]|\[tool\.poetry\.scripts\]'
$rxSha256Word  = '(?im)\bsha256\b'
$rxManifest    = '(?im)\bmanifest\b'
$rxEd25519     = '(?im)\bed25519\b'
$rxRsa         = '(?im)\brsa\b'
$rxSign        = '(?im)\bsign\b'
$rxVerify      = '(?im)\bverify\b'
$rxZipTar      = '(?im)\b(zipfile|tarfile)\b'
$rxCompress    = '(?im)\bcompress\b'
$rxMacriumWord = '(?im)\bmacrium\b'
$rxWindowsOnly = '(?im)\bwin32\b|\bwindows\b|\bpowershell\b'

$checks = @()
$id = 0

# ----------------------------
# AREA: Harness (weights high because it gates determinism)
# ----------------------------
$id++; AddCheck ([ref]$checks) $id "Harness" "Harness scorer exists" 8 (Exists $scoreHarness) "scripts\pipeline_score.ps1 present"
$id++; AddCheck ([ref]$checks) $id "Harness" "safe-run present" 8 (Exists $safeRun) "scripts\safe-run.ps1 present"
$id++; AddCheck ([ref]$checks) $id "Harness" "safe-paste present" 8 (Exists $safePaste) "scripts\safe-paste.ps1 present"

# ----------------------------
# AREA: Packaging / Repo basics
# ----------------------------
$id++; AddCheck ([ref]$checks) $id "Packaging" "pyproject present" 6 (Exists $pyproject) "pyproject.toml present"
$id++; AddCheck ([ref]$checks) $id "Packaging" "pyproject has legacy-doctor name" 4 (Has $tPyproject $rxTomlName) "project name set"
$id++; AddCheck ([ref]$checks) $id "Packaging" "pyproject has semantic version" 4 (Has $tPyproject $rxVersion) "version = X.Y.Z present"
$id++; AddCheck ([ref]$checks) $id "Packaging" "dependencies declared" 3 (Has $tPyproject $rxDeps) "project dependencies section present"
$id++; AddCheck ([ref]$checks) $id "Packaging" "CLI entrypoint declared" 3 (Has $tPyproject $rxCliEntry) "scripts entrypoint section present"
$id++; AddCheck ([ref]$checks) $id "Repo" "README present" 3 (Exists $readme) "README.md present"
$id++; AddCheck ([ref]$checks) $id "Repo" "LICENSE present" 3 (Exists $license) "LICENSE present"
$id++; AddCheck ([ref]$checks) $id "Repo" "run.ps1 present" 2 (Exists $runPs1) "run.ps1 present"

# ----------------------------
# AREA: API surface
# ----------------------------
$id++; AddCheck ([ref]$checks) $id "API" "api server present" 4 (Exists $apiServer) "src/legacy_doctor/api/server.py present"
$id++; AddCheck ([ref]$checks) $id "API" "api routes present" 4 (Exists $apiRoutes) "src/legacy_doctor/api/routes.py present"
$id++; AddCheck ([ref]$checks) $id "API" "FastAPI referenced" 3 ((Has $tApiServer $rxFastApi) -or (Has $tApiRoutes $rxFastApi)) "FastAPI import/usage detected"
$id++; AddCheck ([ref]$checks) $id "API" "uvicorn referenced" 2 (Has $tApiServer $rxUvicorn) "uvicorn usage detected"
$id++; AddCheck ([ref]$checks) $id "API" "pydantic referenced" 2 ((Has $tApiServer $rxPydantic) -or (Has $tApiRoutes $rxPydantic)) "pydantic usage detected"

# ----------------------------
# AREA: Core capabilities (existence)
# ----------------------------
$id++; AddCheck ([ref]$checks) $id "Core" "doctor orchestrator present" 4 (Exists $pyDoctor) "core/doctor.py present"
$id++; AddCheck ([ref]$checks) $id "Core" "doctor engine present" 4 (Exists $pyEngDoctor) "core/doctor_engine.py present"
$id++; AddCheck ([ref]$checks) $id "Core" "powershell bridge present" 3 (Exists $pyPowerShell) "core/powershell.py present"
$id++; AddCheck ([ref]$checks) $id "Core" "paths present" 2 (Exists $pyPaths) "core/paths.py present"
$id++; AddCheck ([ref]$checks) $id "Core" "winprobe present (windows-only signal)" 2 (Exists $pyWinProbe) "core/winprobe.py present"

# ----------------------------
# AREA: Artifacts + crypto (light signal checks)
# ----------------------------
$id++; AddCheck ([ref]$checks) $id "Artifacts" "artifacts module present" 6 (Exists $pyArtifacts) "core/artifacts.py present"
$id++; AddCheck ([ref]$checks) $id "Artifacts" "artifact mentions sha256" 3 (Has $tArtifacts $rxSha256Word) "sha256 referenced in artifacts"
$id++; AddCheck ([ref]$checks) $id "Artifacts" "artifact mentions manifest" 3 (Has $tArtifacts $rxManifest) "manifest referenced in artifacts"
$id++; AddCheck ([ref]$checks) $id "Crypto" "crypto bundle present" 6 (Exists $pyCrypto) "core/crypto_bundle.py present"
$id++; AddCheck ([ref]$checks) $id "Crypto" "keys module present" 5 (Exists $pyKeys) "core/keys.py present"
$id++; AddCheck ([ref]$checks) $id "Crypto" "crypto mentions sign" 3 (Has $tCrypto $rxSign) "sign referenced"
$id++; AddCheck ([ref]$checks) $id "Crypto" "crypto mentions verify" 3 (Has $tCrypto $rxVerify) "verify referenced"
$id++; AddCheck ([ref]$checks) $id "Crypto" "ed25519 or rsa referenced" 2 ((Has $tCrypto $rxEd25519) -or (Has $tCrypto $rxRsa) -or (Has $tKeys $rxEd25519) -or (Has $tKeys $rxRsa)) "key algo referenced"

# ----------------------------
# AREA: Engines (existence + minimal signal)
# ----------------------------
$id++; AddCheck ([ref]$checks) $id "Engines" "image engine present" 6 (Exists $pyEngImage) "core/image_engine.py present"
$id++; AddCheck ([ref]$checks) $id "Engines" "verify engine present" 6 (Exists $pyEngVerify) "core/verify_engine.py present"
$id++; AddCheck ([ref]$checks) $id "Engines" "repair engine present" 6 (Exists $pyEngRepair) "core/repair_engine.py present"
$id++; AddCheck ([ref]$checks) $id "Engines" "wipe engine present" 6 (Exists $pyEngWipe) "core/wipe_engine.py present"
$id++; AddCheck ([ref]$checks) $id "Engines" "export engine present" 4 (Exists $pyEngExport) "core/export_engine.py present"
$id++; AddCheck ([ref]$checks) $id "Engines" "library engine present" 5 (Exists $pyEngLibrary) "core/library_engine.py present"
$id++; AddCheck ([ref]$checks) $id "Engines" "eject present" 2 (Exists $pyEject) "core/eject.py present"

# “Macrium-grade” is a claim — only count if you literally document or implement it
$id++; AddCheck ([ref]$checks) $id "Imaging" "mentions macrium (only if you actually target it)" 1 (Has $tEngImage $rxMacriumWord) "macrium mentioned"

# ----------------------------
# AREA: Compression/archive signals
# ----------------------------
$id++; AddCheck ([ref]$checks) $id "Archive" "compression libs referenced in library/image" 2 ((Has $tEngLib $rxZipTar) -or (Has $tEngImage $rxZipTar) -or (Has $tEngLib $rxCompress) -or (Has $tEngImage $rxCompress)) "zip/tar/compress signal"

# ----------------------------
# AREA: Docs / governance (optional now; score reflects reality)
# ----------------------------
$id++; AddCheck ([ref]$checks) $id "Docs" "spec doc present" 3 (Exists $specDoc) "docs/spec.md present"
$id++; AddCheck ([ref]$checks) $id "Docs" "artifact format doc present" 3 (Exists $artifactDoc) "docs/artifact-format-v1.md present"
$id++; AddCheck ([ref]$checks) $id "Docs" "threat model doc present" 2 (Exists $threatDoc) "docs/threat-model.md present"
$id++; AddCheck ([ref]$checks) $id "Docs" "ops doc present" 2 (Exists $opsDoc) "docs/ops.md present"
$id++; AddCheck ([ref]$checks) $id "Docs" "licensing doc present" 2 (Exists $licenseDoc) "docs/licensing.md present"

# ----------------------------
# AREA: Platform reality check
# ----------------------------
# This doesn’t “fail” anything; it reports whether the tree is currently Windows-centric.
$id++; AddCheck ([ref]$checks) $id "Platform" "Windows-centric signals present" 1 ((Has $tApiServer $rxWindowsOnly) -or (Exists $pyWinProbe) -or (Exists $safeRun)) "signals suggest Windows-first implementation"

# ----------------------------
# Score
# ----------------------------
$weightTotal = 0
$weightPassed = 0
foreach($c in $checks){
  $weightTotal += [int]$c.weight
  if($c.pass){ $weightPassed += [int]$c.weight }
}

$pct = 0
if($weightTotal -gt 0){ $pct = [math]::Round(($weightPassed / [double]$weightTotal) * 100.0, 2) }

Write-Host "LEGACY DOCTOR CANONICAL SCORE"
Write-Host ("Root: {0}" -f $Root)
Write-Host ("Weighted Canonical %: {0}%  (passedWeight={1} totalWeight={2})" -f $pct, $weightPassed, $weightTotal) -ForegroundColor Cyan
Write-Host ""

# Grouped print
$areas = $checks | Group-Object area
foreach($g in $areas){
  Write-Host ("[{0}]" -f $g.Name) -ForegroundColor White
  foreach($c in $g.Group){
    $mark = if($c.pass){ "[PASS]" } else { "[FAIL]" }
    Write-Host ("  {0} (w={1}) #{2} {3} - {4}" -f $mark, $c.weight, $c.id, $c.name, $c.detail)
  }
  Write-Host ""
}

if($EmitJson){
  $obj = [pscustomobject]@{
    root=$Root
    percent=$pct
    passedWeight=$weightPassed
    totalWeight=$weightTotal
    checks=$checks
  }
  $json = $obj | ConvertTo-Json -Depth 6
  Write-Host $json
}