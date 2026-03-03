from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Any

from legacy_doctor.core.winprobe import _run_pwsh
from legacy_doctor.core.artifacts import canonical_json_bytes, sha256_hex_bytes, write_bytes, write_text_utf8_lf


CONFIRM_PHRASE = "I_UNDERSTAND_CHKDSK_CAN_CAUSE_DATA_LOSS"


def _default_job_root() -> Path:
    import os
    base = os.environ.get("LOCALAPPDATA") or str(Path.home())
    d = Path(base) / "LegacyDoctor" / "repair"
    d.mkdir(parents=True, exist_ok=True)
    return d


def run_chkdsk(drive_letter: str, mode: str, confirm: str | None) -> dict[str, Any]:
    dl = drive_letter.rstrip(":").upper()

    if mode not in ("dry_run", "run"):
        raise ValueError("mode must be dry_run or run")

    if mode == "run":
        if confirm != CONFIRM_PHRASE:
            raise ValueError(f"mode=run requires confirm='{CONFIRM_PHRASE}'")

    if mode == "dry_run":
        cmd = f"chkdsk {dl}:"
    else:
        cmd = f"chkdsk {dl}: /f"

    ps = rf"""
$ErrorActionPreference="Continue";
cmd.exe /c "{cmd}" 2>&1
"""

    needs_admin = False
    out_lines: list[str] = []
    ran = False

    try:
        out = _run_pwsh(ps)
        ran = True
        out_lines = (out or "").splitlines()
    except subprocess.CalledProcessError as e:
        ran = True
        text = (e.output or "").strip()
        out_lines = text.splitlines()
        lower = text.lower()
        if "access is denied" in lower or "requires elevation" in lower or "elevated" in lower:
            needs_admin = True

    tail = out_lines[-40:] if len(out_lines) > 40 else out_lines

    return {
        "drive_letter": dl,
        "mode": mode,
        "ran": ran,
        "needs_admin": needs_admin,
        "command": cmd,
        "output_tail": tail,
    }


def run_chkdsk_and_write(drive_letter: str, mode: str, confirm: str | None, job_root: str | None) -> dict[str, Any]:
    rep = run_chkdsk(drive_letter, mode=mode, confirm=confirm)

    jr = Path(job_root) if job_root else _default_job_root()
    jr.mkdir(parents=True, exist_ok=True)

    report_path = jr / "repair_report.json"
    b = canonical_json_bytes(rep)
    write_bytes(report_path, b)

    digest = sha256_hex_bytes(b)
    sha_path = jr / "repair_report.json.sha256"
    write_text_utf8_lf(sha_path, digest + "\n")

    rep["wrote_report"] = True
    rep["report_path"] = str(report_path)
    rep["report_sha256_path"] = str(sha_path)
    return rep
