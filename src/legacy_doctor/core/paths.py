from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path


def utc_run_id() -> str:
    # Example: 20260128_153012Z
    return datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%SZ")


@dataclass(frozen=True)
class StagingPaths:
    base: Path
    device_letter: str
    run_id: str

    @property
    def device_root(self) -> Path:
        return self.base / f"device_{self.device_letter}"

    @property
    def export_root(self) -> Path:
        return self.device_root / "exports" / self.run_id

    @property
    def export_files_root(self) -> Path:
        return self.export_root / "files"

    @property
    def export_log_path(self) -> Path:
        return self.export_root / "export.log"

    @property
    def manifest_root(self) -> Path:
        return self.device_root / "manifests" / f"{self.device_letter}_{self.run_id}"

    @property
    def manifest_path(self) -> Path:
        return self.manifest_root / "manifest.json"

    @property
    def sha256sums_path(self) -> Path:
        return self.manifest_root / "sha256sums.txt"


def default_staging_base() -> Path:
    # %USERPROFILE%\LegacyDoctor\staging
    return Path.home() / "LegacyDoctor" / "staging"
