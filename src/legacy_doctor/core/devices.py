import os
import psutil
from legacy_doctor.models.device import Device


def _is_ipod_legacy(mount: str) -> bool:
    markers = [
        "iPod_Control",
        "iTunes_Control"
    ]
    return any(os.path.exists(os.path.join(mount, m)) for m in markers)


def list_devices() -> list[Device]:
    devices: list[Device] = []

    for p in psutil.disk_partitions(all=False):
        # skip system volumes
        if not p.fstype:
            continue

        try:
            usage = psutil.disk_usage(p.mountpoint)
        except PermissionError:
            continue

        dev_type = "UMS_GENERIC"
        if _is_ipod_legacy(p.mountpoint):
            dev_type = "IPOD_LEGACY"

        devices.append(
            Device(
                id=p.device,
                mount=p.mountpoint,
                fstype=p.fstype,
                total_bytes=usage.total,
                used_bytes=usage.used,
                free_bytes=usage.free,
                percent_used=round(usage.percent, 2),
                type=dev_type,
            )
        )

    return devices
