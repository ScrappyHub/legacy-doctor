from __future__ import annotations

from pydantic import BaseModel, Field
from typing import Literal, Optional


class LibraryIndexRequest(BaseModel):
    source_dir: str  # export_files_root
    drive_letter: str
    run_id: str


class LibraryIndexResult(BaseModel):
    manifest_path: str
    sha256sums_path: str
    file_count: int
    total_bytes: int
    notes: list[str] = Field(default_factory=list)


class LibraryRestoreRequest(BaseModel):
    manifest_path: str
    source_dir: str
    target_root: str  # like "E:\"
    mode: Literal["dry_run", "run"] = "dry_run"
    overwrite: bool = False


class LibraryRestoreResult(BaseModel):
    target_root: str
    files_planned: int
    files_written: int
    files_skipped: int
    bytes_written: int
    errors: list[str] = Field(default_factory=list)
    notes: list[str] = Field(default_factory=list)
