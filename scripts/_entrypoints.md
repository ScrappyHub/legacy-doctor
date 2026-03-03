# Legacy Doctor — Entry Points (PS5.1)

## Canonical entrypoint (ALWAYS use this)
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run.ps1
```

## Self-check
```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\selfcheck.ps1
```

## Components (do not run directly)
- scripts\doctor.ps1 — orchestrator (expects entrypoint contract)
- scripts\gate-ps51.ps1 — PS5.1 compat scan (runs via run.ps1)
- scripts\engine-package.ps1 — packages a completed run directory
