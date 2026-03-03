from __future__ import annotations

import hashlib
import json
import subprocess
from typing import Any

from legacy_doctor.core.winprobe import _run_pwsh, get_partition_info, get_disk_info


CONFIRM_ERASE = "I_UNDERSTAND_THIS_WILL_ERASE_DATA"


def _safety_token(disk_number: int, size: int | None, bus: str | None) -> str:
    seed = f"disk={disk_number};size={size or 0};bus={bus or ''}"
    return hashlib.sha256(seed.encode("utf-8")).hexdigest()


def wipe_plan(drive_letter: str, method: str) -> dict[str, Any]:
    dl = drive_letter.rstrip(":").upper()
    if method not in ("quick_format", "full_format"):
        raise ValueError("method must be quick_format or full_format")

    part = get_partition_info(dl)
    if not isinstance(part, dict) or "DiskNumber" not in part:
        raise ValueError(f"Drive {dl}: is not mounted/accessible or has no partition info.")

    disk_number = part.get("DiskNumber")
    if not isinstance(disk_number, int):
        raise ValueError("Could not resolve disk number")

    disk = get_disk_info(disk_number) or {}
    bus = disk.get("BusType") if isinstance(disk, dict) else None
    size = disk.get("Size") if isinstance(disk, dict) else None
    size_int = int(size) if isinstance(size, int) or isinstance(size, float) else None

    # System disk checks (best effort via PowerShell for IsSystem/IsBoot)
    ps = rf"""
$ErrorActionPreference="Stop";
$d = Get-Disk -Number {disk_number} | Select-Object Number,IsSystem,IsBoot,BusType,Size | ConvertTo-Json -Depth 4;
$d
"""
    meta = {}
    try:
        raw = _run_pwsh(ps)
        if raw:
            meta = json.loads(raw)
    except Exception:
        meta = {}

    is_system = bool(meta.get("IsSystem")) if isinstance(meta, dict) else False
    is_boot = bool(meta.get("IsBoot")) if isinstance(meta, dict) else False

    warnings: list[str] = []
    if is_system or is_boot:
        warnings.append("This appears to be a system/boot disk. Wipe is BLOCKED by design.")

    token = _safety_token(disk_number, size_int, str(bus) if bus is not None else None)

    recommended = [
        "Export / verify before wiping if you care about the data.",
        "Double-check drive letter and disk number in Disk Management.",
        "Use quick_format for normal reuse; full_format for a slower overwrite-by-format.",
    ]

    return {
        "drive_letter": dl,
        "method": method,
        "disk_number": disk_number,
        "is_system_disk": is_system,
        "is_boot_disk": is_boot,
        "bus_type": bus,
        "size_bytes": size_int,
        "safety_token": token,
        "warnings": warnings,
        "recommended_steps": recommended,
    }


def wipe_run(drive_letter: str, req: dict[str, Any]) -> dict[str, Any]:
    dl = drive_letter.rstrip(":").upper()
    method = req.get("method")
    confirm = req.get("confirm")
    safety_token = req.get("safety_token")
    filesystem = req.get("filesystem") or "exFAT"
    new_label = req.get("new_label")

    if method not in ("quick_format", "full_format"):
        raise ValueError("method must be quick_format or full_format")
    if confirm != CONFIRM_ERASE:
        raise ValueError(f"confirm must equal {CONFIRM_ERASE}")
    if not isinstance(safety_token, str) or len(safety_token) < 32:
        raise ValueError("missing safety_token")

    plan = wipe_plan(dl, method)
    if plan["is_system_disk"] or plan["is_boot_disk"]:
        raise ValueError("Refusing to wipe a system/boot disk.")

    if safety_token != plan["safety_token"]:
        raise ValueError("safety_token mismatch (disk identity changed or wrong token).")

    full_flag = "$true" if method == "full_format" else "$false"
    label_expr = f"-NewFileSystemLabel {json.dumps(str(new_label))}" if new_label else ""

    ps = rf"""
$ErrorActionPreference="Continue";
try {{
  Format-Volume -DriveLetter {dl} -FileSystem {filesystem} -Full:{full_flag} -Force -Confirm:$false {label_expr} 2>&1
}} catch {{
  $_ | Out-String
}}
"""

    needs_admin = False
    out_lines: list[str] = []
    try:
        out = _run_pwsh(ps)
        out_lines = (out or "").splitlines()
        low = (out or "").lower()
        if "access is denied" in low or "administrator" in low:
            needs_admin = True
    except subprocess.CalledProcessError as e:
        text = (e.output or "").strip()
        out_lines = text.splitlines()
        low = text.lower()
        if "access is denied" in low or "administrator" in low:
            needs_admin = True

    tail = out_lines[-60:] if len(out_lines) > 60 else out_lines

    return {
        "drive_letter": dl,
        "method": method,
        "ran": True,
        "needs_admin": needs_admin,
        "output_tail": tail,
    }
