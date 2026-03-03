from legacy_doctor.core.capabilities import get_capabilities
from legacy_doctor.core.winprobe import (
    try_eject_shell_verb,
    try_mountvol_remove,
    try_cim_dismount_remove,
)
from legacy_doctor.models.eject import EjectResult

def eject_device(drive_letter: str) -> EjectResult:
    caps = get_capabilities(drive_letter)

    warnings: list[str] = []
    if (caps.bus_type or "").upper() != "USB":
        raise ValueError("Refusing to eject: target is not USB-removable")

    if caps.health_status and caps.health_status.lower() != "healthy":
        warnings.append(f"Volume health is '{caps.health_status}'")

    # Tier 1: Shell Eject verb
    ok, raw = try_eject_shell_verb(caps.drive_letter)
    if ok:
        return EjectResult(
            drive_letter=caps.drive_letter,
            disk_number=caps.disk_number,
            status="ejected",
            method="shell_eject",
            warnings=warnings,
            raw=raw,
        )

    warnings.append("Shell eject did not succeed (or no eject verb). Trying mountvol…")

    # Tier 2: mountvol /p
    ok, raw2 = try_mountvol_remove(caps.drive_letter)
    if ok:
        return EjectResult(
            drive_letter=caps.drive_letter,
            disk_number=caps.disk_number,
            status="ejected",
            method="mountvol_p",
            warnings=warnings,
            raw=raw2,
        )

    warnings.append("mountvol did not succeed. Trying Win32_Volume Dismount/Remove…")

    # Tier 3: CIM Dismount/Remove
    ok, raw3 = try_cim_dismount_remove(caps.drive_letter)
    if ok:
        return EjectResult(
            drive_letter=caps.drive_letter,
            disk_number=caps.disk_number,
            status="ejected",
            method="cim_dismount_remove",
            warnings=warnings,
            raw=raw3,
        )

    return EjectResult(
        drive_letter=caps.drive_letter,
        disk_number=caps.disk_number,
        status="failed",
        method="cim_dismount_remove",
        warnings=warnings,
        error="All eject methods failed",
        raw="\n---shell---\n" + raw + "\n---mountvol---\n" + raw2 + "\n---cim---\n" + raw3,
    )
