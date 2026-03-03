from __future__ import annotations

from pydantic import BaseModel, Field
from typing import Literal, Optional


class ExportPlan(BaseModel):
    drive_letter: str
    source_root: str
    export_root: str
    export_files_root: str
    run_id: str
    estimated_file_count: int = 0
    notes: list[str] = Field(default_factory=list)


class ExportRunRequest(BaseModel):
    mode: Literal["dry_run", "run"] = "dry_run"
    resume: bool = True
    overwrite: bool = False
    # Optional: restrict to common media extensions
    media_only: bool = True


class ExportRunResult(BaseModel):
    drive_letter: str
    run_id: str
    export_root: str
    export_files_root: str
    log_path: str
    files_copied: int
    files_skipped: int
    bytes_copied: int
    errors: list[str] = Field(default_factory=list)
    notes: list[str] = Field(default_factory=list)
