import re

from legacy_doctor.core.devices import list_devices
from legacy_doctor.core.winprobe import (
    get_disk_info,
    get_partition_info,
    get_volume_info,
    set_volume_label,
)
from legacy_doctor.models.capabilities import DeviceCapabilities, RenameResult

_LABEL_RE = re.compile(r"^[A-Za-z0-9 _\-]{1,11}$")  # FAT-style safe label


def _normalize_drive_letter(drive_letter: str) -> str:
    dl = drive_letter.strip().rstrip(":").upper()
    if len(dl) != 1 or not ("A" <= dl <= "Z"):
        raise ValueError("Invalid drive letter")
    return dl


def get_capabilities(drive_letter: str) -> DeviceCapabilities:
    dl = _normalize_drive_letter(drive_letter)
    mount = f"{dl}:\\"

    vol = get_volume_info(dl) or {}
    part = get_partition_info(dl) or {}

    disk_num = part.get("DiskNumber")
    disk = get_disk_info(int(disk_num)) if disk_num is not None else {}

    # Determine type using our existing device scan (psutil + markers)
    dev_type = "UNKNOWN"
    for d in list_devices():
        if d.mount.upper() == mount.upper():
            dev_type = d.type
            break

    allowed_fs: list[str] = []
    warnings: list[str] = []

    fs = vol.get("FileSystemType")
    health = vol.get("HealthStatus")
    op_status = vol.get("OperationalStatus") or []
    if isinstance(op_status, str):
        op_status = [op_status]

    if health and str(health).lower() != "healthy":
        warnings.append(f"Volume health is '{health}'")
    if any("repair" in str(s).lower() for s in op_status):
        warnings.append("Volume reports it may need repair (OperationalStatus contains 'Repair')")

    # Policy: iPod legacy -> FAT32 only (safe baseline)
    if dev_type == "IPOD_LEGACY":
        allowed_fs = ["FAT32"]
    else:
        # Generic removable: conservative
        allowed_fs = ["FAT32", "exFAT"]

    return DeviceCapabilities(
        drive_letter=dl,
        mount=mount,
        disk_number=disk.get("Number"),
        disk_friendly_name=disk.get("FriendlyName"),
        bus_type=disk.get("BusType"),
        filesystem=fs,
        volume_label=vol.get("FileSystemLabel"),
        size_bytes=vol.get("Size"),
        size_remaining_bytes=vol.get("SizeRemaining"),
        health_status=health,
        operational_status=op_status,
        allowed_filesystems=allowed_fs,
        warnings=warnings,
    )


def rename_volume(drive_letter: str, new_label: str) -> RenameResult:
    dl = _normalize_drive_letter(drive_letter)
    caps = get_capabilities(dl)

    # Hard safety gate: USB-only or iPod-identified
    is_usb = (caps.bus_type or "").upper() == "USB"
    is_ipod = "ipod" in (caps.disk_friendly_name or "").lower()
    if not (is_usb or is_ipod):
        raise ValueError("Refusing to rename: target is not USB-removable")

    if not _LABEL_RE.match(new_label):
        raise ValueError("Invalid label. Use 1-11 chars: letters/numbers/space/_/- only.")

    old = caps.volume_label
    set_volume_label(dl, new_label)
    return RenameResult(drive_letter=dl, old_label=old, new_label=new_label)
