from __future__ import annotations

from pathlib import Path
from typing import Any

from legacy_doctor.core.winprobe import get_volume_info, get_partition_info, get_disk_info
from legacy_doctor.core.artifacts import canonical_json_bytes, sha256_hex_bytes, write_bytes, write_text_utf8_lf


def _default_job_root() -> Path:
    # job root concept: for doctor-only reports, keep a stable location
    # (later you can unify under a job folder naming scheme)
    import os
    base = os.environ.get("LOCALAPPDATA") or str(Path.home())
    d = Path(base) / "LegacyDoctor" / "doctor"
    d.mkdir(parents=True, exist_ok=True)
    return d


def doctor_usb(drive_letter: str) -> dict[str, Any]:
    dl = drive_letter.rstrip(":").upper()

    vol = get_volume_info(dl)
    part = get_partition_info(dl)
    disk = None

    warnings: list[str] = []

    if not vol:
        return {
            "drive_letter": dl,
            "volume": None,
            "partition": None,
            "disk": None,
            "warnings": [f"Drive {dl}: not found/mounted."],
        }

    # Join disk via partition
    if isinstance(part, dict):
        dn = part.get("DiskNumber")
        if isinstance(dn, int):
            disk = get_disk_info(dn)

    # Heuristics (conservative)
    fs = (vol.get("FileSystemType") or "Unknown")
    hs = (vol.get("HealthStatus") or "")
    ops = (vol.get("OperationalStatus") or "")

    if isinstance(hs, str) and hs and hs.lower() not in ("healthy",):
        warnings.append(f"HealthStatus={hs}")

    if isinstance(ops, str) and ops and ("ok" not in ops.lower()) and ("online" not in ops.lower()):
        warnings.append(f"OperationalStatus={ops}")

    if str(fs).lower() == "unknown":
        warnings.append("File system type is Unknown (may be unmounted, raw, or special device).")

    if disk and isinstance(disk, dict):
        op = disk.get("OperationalStatus")
        # OperationalStatus may be list or string depending on PS formatting
        if isinstance(op, list):
            if any(str(x).lower() not in ("online",) for x in op):
                warnings.append(f"Disk OperationalStatus={op}")
        elif isinstance(op, str) and op and op.lower() not in ("online", "ok", "healthy"):
            warnings.append(f"Disk OperationalStatus={op}")

    return {
        "drive_letter": dl,
        "volume": vol,
        "partition": part,
        "disk": disk,
        "warnings": warnings,
    }


def doctor_usb_and_write(drive_letter: str, job_root: str | None) -> dict[str, Any]:
    rep = doctor_usb(drive_letter)

    jr = Path(job_root) if job_root else _default_job_root()
    jr.mkdir(parents=True, exist_ok=True)

    # report.json + sha256
    report_path = jr / "report.json"
    b = canonical_json_bytes(rep)
    write_bytes(report_path, b)

    digest = sha256_hex_bytes(b)
    sha_path = jr / "report.json.sha256"
    write_text_utf8_lf(sha_path, digest + "\n")

    rep["wrote_report"] = True
    rep["report_path"] = str(report_path)
    rep["report_sha256_path"] = str(sha_path)
    return rep
