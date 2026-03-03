from __future__ import annotations

import json
from legacy_doctor.core.powershell import run_ps
from legacy_doctor.models.repair import RepairCheck, ChkdskRequest, ChkdskResult


def _norm_dl(drive_letter: str) -> str:
    dl = (drive_letter or "").strip().upper()
    if len(dl) != 1 or not dl.isalpha():
        raise ValueError(f"Invalid drive_letter: {drive_letter!r}")
    return dl


def repair_check(drive_letter: str) -> RepairCheck:
    dl = _norm_dl(drive_letter)

    # Use Get-Volume because it's already in your canonical toolchain.
    # When devices are in a weird state, this may return FileSystemType=Unknown and Size=0.
    ps = rf"""
$ErrorActionPreference="Stop";
$dl = "{dl}";
$vol = Get-Volume -DriveLetter $dl -ErrorAction SilentlyContinue |
  Select-Object DriveLetter,FileSystemLabel,FileSystemType,HealthStatus,OperationalStatus,Size,SizeRemaining |
  ConvertTo-Json -Depth 6;
$vol
"""
    r = run_ps(ps)

    chk = RepairCheck(drive_letter=dl)
    chk.raw["get_volume_exit_code"] = r.exit_code
    chk.raw["get_volume_stdout"] = r.stdout
    chk.raw["get_volume_stderr"] = r.stderr

    if r.exit_code == 0 and r.stdout.strip():
        try:
            v = json.loads(r.stdout)
        except Exception:
            v = None

        if isinstance(v, dict):
            chk.filesystem = v.get("FileSystemType")
            chk.volume_label = v.get("FileSystemLabel")
            chk.health_status = v.get("HealthStatus")
            op = v.get("OperationalStatus")
            if isinstance(op, list):
                chk.operational_status = [str(x) for x in op]
            elif op is not None:
                chk.operational_status = [str(op)]
            try:
                chk.size_bytes = int(v.get("Size")) if v.get("Size") is not None else None
            except Exception:
                pass
            try:
                chk.size_remaining_bytes = int(v.get("SizeRemaining")) if v.get("SizeRemaining") is not None else None
            except Exception:
                pass

    # Canonical warnings / recos
    if chk.filesystem is None:
        chk.warnings.append("Get-Volume did not return a parsable result.")
    if (chk.filesystem or "").lower() == "unknown" or (chk.size_bytes == 0):
        chk.warnings.append("Volume appears unstable (FileSystemType=Unknown and/or Size=0).")

    chk.recommendations.append("Replug device (different USB port), then re-run repair/check.")
    chk.recommendations.append("If FAT32 device: run chkdsk in dry_run mode first.")
    chk.recommendations.append("If still unstable: driver refresh (Device Manager -> Disk drives -> uninstall device -> scan).")

    return chk


def run_chkdsk(drive_letter: str, req: ChkdskRequest) -> ChkdskResult:
    dl = _norm_dl(drive_letter)
    mode = req.mode

    # We do NOT attempt elevation inside the API. If not admin, chkdsk /f will fail.
    # dry_run uses plain chkdsk which is generally safe/read-only.
    if mode == "dry_run":
        cmd = f'chkdsk {dl}:'
    else:
        cmd = f'chkdsk {dl}: /f'

    ps = rf"""
$ErrorActionPreference="Continue";
{cmd} 2>&1 | Out-String
"""
    r = run_ps(ps)

    out = (r.stdout or "").strip()
    err = (r.stderr or "").strip()

    res = ChkdskResult(
        drive_letter=dl,
        mode=mode,
        exit_code=r.exit_code,
        stdout=out,
        stderr=err,
    )

    if mode == "fix" and r.exit_code != 0:
        res.warnings.append("chkdsk /f likely requires an elevated (Administrator) shell.")
        res.recommendations.append("Run the same command in an elevated PowerShell, then re-run repair/check.")
    else:
        res.recommendations.append("Re-run repair/check after chkdsk completes.")

    return res
