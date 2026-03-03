param([switch]$NoStart)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Repo-Root {
  $here = Split-Path -Parent $PSCommandPath
  return (Resolve-Path (Join-Path $here "..")).Path
}

function Import-Root {
  param([string]$RepoRoot)
  $src = Join-Path $RepoRoot "src"
  if (Test-Path -LiteralPath $src) { return $src }
  return $RepoRoot
}

function Ensure-Venv {
  param([string]$RepoRoot)
  $venvPy = Join-Path $RepoRoot ".venv\Scripts\python.exe"

  if (-not (Test-Path -LiteralPath $venvPy)) {
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) { & py -3 -m venv (Join-Path $RepoRoot ".venv") }
    else     { & python -m venv (Join-Path $RepoRoot ".venv") }
  }

  if (-not (Test-Path -LiteralPath $venvPy)) { throw "Failed to create venv. Expected: $venvPy" }
  return $venvPy
}

function Pip-Install {
  param([string]$VenvPython, [string]$RepoRoot)

  & $VenvPython -m pip install --upgrade pip setuptools wheel | Out-Null

  $req = Join-Path $RepoRoot "requirements.txt"
  if (Test-Path -LiteralPath $req) {
    $txt = Get-Content -LiteralPath $req -ErrorAction Stop
    if ($txt -match '^\s*-e\s+\.\s*$') {
      throw "requirements.txt contains '-e .'. Remove it or comment it out."
    }
    & $VenvPython -m pip install -r $req | Out-Null
  }

  # Optional editable install; safe only if pyproject is valid (BOM already fixed)
  $pyproject = Join-Path $RepoRoot "pyproject.toml"
  if (Test-Path -LiteralPath $pyproject) {
    & $VenvPython -m pip install -e $RepoRoot | Out-Null
  }
}

function Detect-AppSpec {
  param([string]$VenvPython, [string]$ImportRoot, [string]$RepoRoot)

  $tmpDir = Join-Path $RepoRoot ".tmp"
  New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
  $probePath = Join-Path $tmpDir "probe_appspec.py"

  @"
import os, sys, importlib

root = os.environ.get("LD_IMPORT_ROOT")
if not root:
    print("APP_SPEC=NONE")
    raise SystemExit(0)

sys.path.insert(0, root)

# hard candidates based on your repo tree
candidates = [
  "legacy_doctor.api.server:app",
  "legacy_doctor.api.server:create_app",
  "legacy_doctor.api.routes:app",
  "legacy_doctor.api.routes:create_app",
]

def try_spec(spec):
    mod, attr = spec.split(":")
    m = importlib.import_module(mod)
    if not hasattr(m, attr):
        return None
    obj = getattr(m, attr)
    if callable(obj) and attr == "create_app":
        try:
            obj = obj()
        except Exception:
            return None
    return spec

found = None
for s in candidates:
    try:
        if try_spec(s):
            found = s
            break
    except Exception:
        pass

print("APP_SPEC=" + (found or "NONE"))
"@ | Set-Content -LiteralPath $probePath -Encoding UTF8

  $env:LD_IMPORT_ROOT = $ImportRoot

  # IMPORTANT: capture as a single string
  $out = & $VenvPython $probePath 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) {
    throw ("AppSpec probe failed:`n" + $out)
  }

  $m = [regex]::Match($out, 'APP_SPEC=(.+)')
  if (-not $m.Success) { return "NONE" }
  return $m.Groups[1].Value.Trim()
}

try {
  $repoRoot   = Repo-Root
  $importRoot = Import-Root -RepoRoot $repoRoot
  $venvPy     = Ensure-Venv -RepoRoot $repoRoot

  Pip-Install -VenvPython $venvPy -RepoRoot $repoRoot

  $appSpec = Detect-AppSpec -VenvPython $venvPy -ImportRoot $importRoot -RepoRoot $repoRoot
  if ($appSpec -eq "NONE") {
    throw "No ASGI app export found. Expected something like legacy_doctor.api.server:app"
  }

  if ($NoStart) { exit 0 }

  & (Join-Path $repoRoot "scripts\ensure-server.ps1") -AppSpec $appSpec
  exit $LASTEXITCODE
}
catch {
  [Console]::Error.WriteLine("BOOTSTRAP_ERROR: " + $_.Exception.ToString())
  exit 1
}
