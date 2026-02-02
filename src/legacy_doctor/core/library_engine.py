from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Iterable

from legacy_doctor.core.paths import StagingPaths, default_staging_base


def _iter_files(root: Path) -> Iterable[Path]:
    for p in root.rglob("*"):
        if p.is_file():
            yield p


def sha256_file(path: Path, chunk_size: int = 1024 * 1024) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        while True:
            b = f.read(chunk_size)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


def index_library(source_dir: str, drive_letter: str, run_id: str) -> dict:
    src = Path(source_dir)
    if not src.exists() or not src.is_dir():
        raise ValueError(f"source_dir does not exist or is not a directory: {source_dir}")

    dl = drive_letter.rstrip(":").upper()
    sp = StagingPaths(base=default_staging_base(), device_letter=dl, run_id=run_id)
    sp.manifest_root.mkdir(parents=True, exist_ok=True)

    files = []
    total_bytes = 0

    for p in _iter_files(src):
        rel = p.relative_to(src)
        size = p.stat().st_size
        total_bytes += size
        digest = sha256_file(p)
        files.append(
            {
                "relpath": str(rel).replace("\\", "/"),
                "size": size,
                "sha256": digest,
            }
        )

    manifest = {
        "schema": "legacy_doctor.manifest.v1",
        "drive_letter": dl,
        "run_id": run_id,
        "source_dir": str(src),
        "file_count": len(files),
        "total_bytes": total_bytes,
        "files": files,
    }

    sp.manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    # sha256sums.txt like: "<sha256>  <relpath>"
    lines = []
    for f in files:
        lines.append(f"{f['sha256']}  {f['relpath']}")
    sp.sha256sums_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    return {
        "manifest_path": str(sp.manifest_path),
        "sha256sums_path": str(sp.sha256sums_path),
        "file_count": len(files),
        "total_bytes": total_bytes,
        "notes": ["manifest.json + sha256sums.txt written (tamper-evident by hash)."],
    }


def restore_library(manifest_path: str, source_dir: str, target_root: str, mode: str, overwrite: bool) -> dict:
    mp = Path(manifest_path)
    if not mp.exists():
        raise ValueError(f"manifest_path not found: {manifest_path}")

    src = Path(source_dir)
    if not src.exists():
        raise ValueError(f"source_dir not found: {source_dir}")

    trg = Path(target_root)
    if not trg.exists():
        raise ValueError(f"target_root not found/mounted: {target_root}")

    manifest = json.loads(mp.read_text(encoding="utf-8"))
    files = manifest.get("files") or []

    planned = 0
    written = 0
    skipped = 0
    bytes_written = 0
    errors: list[str] = []
    notes: list[str] = []

    for f in files:
        planned += 1
        rel = Path(f["relpath"])
        src_path = src / rel
        dst_path = trg / rel

        try:
            if not src_path.exists():
                skipped += 1
                errors.append(f"Missing source: {src_path}")
                continue

            if dst_path.exists() and not overwrite:
                skipped += 1
                continue

            if mode == "dry_run":
                skipped += 1
                continue

            dst_path.parent.mkdir(parents=True, exist_ok=True)
            dst_path.write_bytes(src_path.read_bytes())
            written += 1
            bytes_written += dst_path.stat().st_size

        except Exception as e:
            errors.append(f"{rel}: {e}")

    if mode == "dry_run":
        notes.append("dry_run=true (no files written).")

    return {
        "target_root": str(trg),
        "files_planned": planned,
        "files_written": written,
        "files_skipped": skipped,
        "bytes_written": bytes_written,
        "errors": errors,
        "notes": notes,
    }
