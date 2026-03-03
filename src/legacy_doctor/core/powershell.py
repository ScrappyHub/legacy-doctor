from __future__ import annotations

import subprocess
from dataclasses import dataclass


@dataclass
class PsRun:
    exit_code: int
    stdout: str
    stderr: str


def run_ps(script: str) -> PsRun:
    """
    Runs PowerShell in a predictable way.
    IMPORTANT: script is passed as a single -Command string.
    """
    p = subprocess.run(
        ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script],
        capture_output=True,
        text=True,
    )
    return PsRun(exit_code=p.returncode, stdout=p.stdout or "", stderr=p.stderr or "")
