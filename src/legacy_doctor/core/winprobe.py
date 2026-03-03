from __future__ import annotations

import json
import subprocess
from typing import Any


def _run_pwsh(script: str) -> str:
    """
    Runs a PowerShell script and returns stdout (string).
    Raises CalledProcessError on non-zero exit.
    """
    # -NoProfile avoids user profile pollution
    # -ExecutionPolicy Bypass for local dev convenience
    cp = subprocess.run(
        ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script],
        capture_output=True,
        text=True,
        check=True,
    )
    return (cp.stdout or "").strip()


def _try_pwsh_json(script: str) -> Any:
    """
    Runs PowerShell that outputs JSON. Returns parsed object or None.
    """
    try:
        out = _run_pwsh(script)
        if not out:
            return None
        return json.loads(out)
    except Exception:
        return None


def list_devices() -> list[dict[str, Any]]:
    """
    Enumerate mounted volumes by drive letter and basic usage.
    Contract matches your current API output (id/mount/fstype/label/bytes).
    """
    ps = r"""
$ErrorActionPreference="Stop";

$vols = Get-Volume | Where-Object { $_.DriveLetter -ne $null } |
  Select-Object DriveLetter,FileSystemType,FileSystemLabel,Size,SizeRemaining,HealthStatus,OperationalStatus |
  ConvertTo-Json -Depth 6;

$vols
"""
    data = _try_pwsh_json(ps)
    if data is None:
        return []

    # Normalize single-object -> list
    if isinstance(data, dict):
        data = [data]

    out: list[dict[str, Any]] = []
    for v in data:
        if not isinstance(v, dict):
            continue
        dl = (v.get("DriveLetter") or "")
        if not isinstance(dl, str) or not dl:
            continue

        size = int(v.get("Size") or 0)
        free = int(v.get("SizeRemaining") or 0)
        used = max(0, size - free)
        pct = round((used / size) * 100.0, 1) if size > 0 else 0.0

        fstype = v.get("FileSystemType") or "Unknown"
        label = v.get("FileSystemLabel") or ""

        out.append(
            {
                "id": f"{dl}:\\",
                "mount": f"{dl}:\\",
                "fstype": str(fstype),
                "label": str(label),
                "total_bytes": size,
                "used_bytes": used,
                "free_bytes": free,
                "percent_used": pct,
                "type": "UMS_GENERIC",
            }
        )
    return out


def get_volume_info(drive_letter: str) -> dict[str, Any] | None:
    dl = drive_letter.rstrip(":").upper()
    ps = rf"""
$ErrorActionPreference="Stop";
$v = Get-Volume -DriveLetter {dl} |
  Select-Object DriveLetter,FileSystemType,FileSystemLabel,Size,SizeRemaining,HealthStatus,OperationalStatus,DriveType,Path |
  ConvertTo-Json -Depth 6;
$v
"""
    data = _try_pwsh_json(ps)
    return data if isinstance(data, dict) else None


def get_partition_info(drive_letter: str) -> dict[str, Any] | None:
    """
    Maps a drive letter to partition metadata including DiskNumber.
    """
    dl = drive_letter.rstrip(":").upper()
    ps = rf"""
$ErrorActionPreference="Stop";
$p = Get-Partition -DriveLetter {dl} |
  Select-Object DriveLetter,DiskNumber,PartitionNumber,GptType,Type,Size,Offset,IsBoot,IsSystem,IsReadOnly,AccessPaths |
  ConvertTo-Json -Depth 6;
$p
"""
    data = _try_pwsh_json(ps)
    return data if isinstance(data, dict) else None


def get_disk_info(disk_number: int) -> dict[str, Any] | None:
    """
    Disk metadata used by wipe/image planning.
    """
    dn = int(disk_number)
    ps = rf"""
$ErrorActionPreference="Stop";
$d = Get-Disk -Number {dn} |
  Select-Object Number,FriendlyName,SerialNumber,BusType,Size,PartitionStyle,IsSystem,IsBoot,IsReadOnly,IsOffline,HealthStatus,OperationalStatus |
  ConvertTo-Json -Depth 6;
$d
"""
    data = _try_pwsh_json(ps)
    return data if isinstance(data, dict) else None
