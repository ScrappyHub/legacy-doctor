from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Any

from legacy_doctor.core.winprobe import _run_pwsh, get_partition_info
from legacy_doctor.core.artifacts import write_sha256sums_txt, sha256_file_hex


CONFIRM_IMAGE_RUN = "I_UNDERSTAND_RAW_IMAGING_CAN_DESTROY_DATA"


def _disk_meta(disk_number: int) -> dict[str, Any]:
    ps = rf"""
$ErrorActionPreference="Stop";
$d = Get-Disk -Number {disk_number} | Select-Object Number,IsSystem,IsBoot,BusType,Size,FriendlyName,OperationalStatus | ConvertTo-Json -Depth 6;
$d
"""
    raw = _run_pwsh(ps)
    return json.loads(raw) if raw else {}


def _safety_token(meta: dict[str, Any]) -> str:
    seed = f"disk={meta.get('Number')};size={meta.get('Size')};bus={meta.get('BusType')};name={meta.get('FriendlyName')}"
    return hashlib.sha256(seed.encode("utf-8")).hexdigest()


def image_plan(drive_letter: str, chunk_bytes: int, output_dir: str | None) -> dict[str, Any]:
    dl = drive_letter.rstrip(":").upper()
    part = get_partition_info(dl)
    if not isinstance(part, dict) or "DiskNumber" not in part:
        raise ValueError(f"Drive {dl}: is not mounted/accessible or has no partition info.")
    disk_number = part["DiskNumber"]
    if not isinstance(disk_number, int):
        raise ValueError("Could not resolve disk number")

    meta = _disk_meta(disk_number)
    is_system = bool(meta.get("IsSystem"))
    is_boot = bool(meta.get("IsBoot"))

    warnings: list[str] = []
    if is_system or is_boot:
        warnings.append("System/boot disks are blocked by default (imaging not permitted).")

    token = _safety_token(meta)

    base = Path(os.environ.get("LOCALAPPDATA") or str(Path.home()))
    outdir = output_dir or str((base / "LegacyDoctor" / "images" / f"disk_{disk_number}").resolve())

    return {
        "drive_letter": dl,
        "disk_number": disk_number,
        "chunk_bytes": int(chunk_bytes),
        "output_dir": outdir,
        "safety_token": token,
        "warnings": warnings,
    }


def image_run(drive_letter: str, req: dict[str, Any]) -> dict[str, Any]:
    dl = drive_letter.rstrip(":").upper()
    chunk_bytes = int(req.get("chunk_bytes") or 8 * 1024 * 1024)
    confirm = req.get("confirm")
    safety_token = req.get("safety_token")
    output_dir = req.get("output_dir")

    if confirm != CONFIRM_IMAGE_RUN:
        raise ValueError(f"confirm must equal {CONFIRM_IMAGE_RUN}")

    plan = image_plan(dl, chunk_bytes, output_dir)
    if plan["warnings"]:
        raise ValueError(plan["warnings"][0])
    if safety_token != plan["safety_token"]:
        raise ValueError("safety_token mismatch")

    disk_number = plan["disk_number"]
    outdir = Path(plan["output_dir"])
    chunks_dir = outdir / "chunks"
    chunks_dir.mkdir(parents=True, exist_ok=True)

    phys = fr"\\.\PhysicalDrive{disk_number}"

    errors: list[str] = []
    written: list[tuple[str, str]] = []

    manifest = {
        "schema": "legacydoctor.image_manifest.v1",
        "image_version": 1,
        "drive_letter": dl,
        "disk_number": disk_number,
        "chunk_bytes": chunk_bytes,
        "device": {"path": phys},
        "chunks": [],
    }

    try:
        with open(phys, "rb", buffering=0) as f:
            idx = 0
            while True:
                buf = f.read(chunk_bytes)
                if not buf:
                    break
                name = f"{idx:06d}.bin"
                p = chunks_dir / name
                p.write_bytes(buf)
                h = sha256_file_hex(p)
                rel = f"chunks/{name}"
                written.append((h, rel))
                manifest["chunks"].append({"path": rel, "size_bytes": len(buf), "sha256": h})
                idx += 1
    except Exception as e:
        errors.append(str(e))

    image_manifest_path = outdir / "image_manifest.json"
    image_manifest_path.write_text(json.dumps(manifest, sort_keys=True, ensure_ascii=False, separators=(",", ":")) + "\n", encoding="utf-8")

    sha256sums_path = write_sha256sums_txt(outdir, written + [(sha256_file_hex(image_manifest_path), "image_manifest.json")])

    status = "completed" if not errors else "partial"

    return {
        "drive_letter": dl,
        "disk_number": disk_number,
        "status": status,
        "output_dir": str(outdir),
        "image_manifest_path": str(image_manifest_path),
        "chunks_dir": str(chunks_dir),
        "sha256sums_path": str(sha256sums_path),
        "errors": errors,
    }
