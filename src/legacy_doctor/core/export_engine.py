from __future__ import annotations

import os
import shutil
from pathlib import Path
from typing import Iterable, Tuple

from legacy_doctor.core.paths import StagingPaths, default_staging_base, utc_run_id

MEDIA_EXTS = {
    ".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tif", ".tiff", ".heic",
    ".mp4", ".mov", ".m4v", ".avi", ".mkv", ".wmv", ".mts", ".m2ts",
    ".mp3", ".m4a", ".aac", ".wav", ".flac", ".wma",
    ".3gp",
}


def _iter_files(root: Path) -> Iterable[Path]:
    for p in root.rglob("*"):
        if p.is_file():
            yield p


def _safe_relpath(p: Path, root: Path) -> Path:
    rp = p.relative_to(root)
    # prevent weirdness
    if any(part in ("..", "") for part in rp.parts):
        raise ValueError("Unsafe relative path detected.")
    return rp


def build_export_paths(drive_letter: str, run_id: str | None = None) -> StagingPaths:
    dl = drive_letter.rstrip(":").upper()
    if len(dl) != 1 or not dl.isalpha():
        raise ValueError("drive_letter must be like 'D' or 'D:'")
    rid = run_id or utc_run_id()
    return StagingPaths(base=default_staging_base(), device_letter=dl, run_id=rid)


def export_plan(drive_letter: str) -> tuple[StagingPaths, dict]:
    dl = drive_letter.rstrip(":").upper()
    source_root = Path(f"{dl}:\\")
    if not source_root.exists():
        raise ValueError(f"Drive {dl}: is not mounted/accessible.")

    sp = build_export_paths(dl)
    sp.export_files_root.mkdir(parents=True, exist_ok=True)
    sp.manifest_root.mkdir(parents=True, exist_ok=True)

    # lightweight estimate: count files in top-level only (fast)
    est = 0
    try:
        for p in source_root.rglob("*"):
            if p.is_file():
                est += 1
                if est >= 5000:  # cap estimate cost
                    break
    except Exception:
        pass

    plan = {
        "drive_letter": dl,
        "source_root": str(source_root),
        "export_root": str(sp.export_root),
        "export_files_root": str(sp.export_files_root),
        "run_id": sp.run_id,
        "estimated_file_count": est,
        "notes": [
            "Export copies files from the mounted drive into a staging folder.",
            "No credentials are bypassed; only readable files are copied.",
        ],
    }
    return sp, plan


def export_run(drive_letter: str, *, mode: str, resume: bool, overwrite: bool, media_only: bool) -> dict:
    dl = drive_letter.rstrip(":").upper()
    source_root = Path(f"{dl}:\\")
    if not source_root.exists():
        raise ValueError(f"Drive {dl}: is not mounted/accessible.")

    sp = build_export_paths(dl)
    sp.export_files_root.mkdir(parents=True, exist_ok=True)

    copied = 0
    skipped = 0
    bytes_copied = 0
    errors: list[str] = []
    notes: list[str] = []

    # resume means: if target exists and overwrite is False => skip
    def should_copy(dst: Path) -> bool:
        if not dst.exists():
            return True
        if overwrite:
            return True
        return False

    with sp.export_log_path.open("a", encoding="utf-8") as log:
        log.write(f"=== Export start: drive={dl} run_id={sp.run_id} mode={mode} ===\n")

        for src in _iter_files(source_root):
            try:
                if media_only and src.suffix.lower() not in MEDIA_EXTS:
                    skipped += 1
                    continue

                rel = _safe_relpath(src, source_root)
                dst = sp.export_files_root / rel
                dst.parent.mkdir(parents=True, exist_ok=True)

                if resume and not should_copy(dst):
                    skipped += 1
                    continue

                if mode == "dry_run":
                    skipped += 1
                    continue

                # copy2 preserves timestamps where possible
                shutil.copy2(src, dst)
                copied += 1
                try:
                    bytes_copied += dst.stat().st_size
                except Exception:
                    pass

            except Exception as e:
                errors.append(f"{src}: {e}")
                log.write(f"ERROR {src}: {e}\n")

        log.write(f"=== Export end: copied={copied} skipped={skipped} bytes={bytes_copied} errors={len(errors)} ===\n")

    if media_only:
        notes.append("media_only=true (filters to common photo/video/audio extensions).")

    return {
        "drive_letter": dl,
        "run_id": sp.run_id,
        "export_root": str(sp.export_root),
        "export_files_root": str(sp.export_files_root),
        "log_path": str(sp.export_log_path),
        "files_copied": copied,
        "files_skipped": skipped,
        "bytes_copied": bytes_copied,
        "errors": errors,
        "notes": notes,
    }
