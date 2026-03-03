from __future__ import annotations

from pydantic import BaseModel, Field
from typing import Literal


class ImagePlanResult(BaseModel):
    drive_letter: str
    disk_number: int
    chunk_bytes: int
    output_dir: str
    safety_token: str
    warnings: list[str]


class ImageRunRequest(BaseModel):
    mode: Literal["plan", "run"] = "run"
    chunk_bytes: int = Field(default=8 * 1024 * 1024, description="Chunk size for imaging (bytes)")
    confirm: str | None = Field(default=None, description="Required for run")
    safety_token: str | None = None
    output_dir: str | None = None


class ImageRunResult(BaseModel):
    drive_letter: str
    disk_number: int
    status: str
    output_dir: str
    image_manifest_path: str
    chunks_dir: str
    sha256sums_path: str
    errors: list[str]


class ImageVerifyRequest(BaseModel):
    output_dir: str


class ImageVerifyResult(BaseModel):
    output_dir: str
    status: str
    mismatches: list[str]
    missing: list[str]


class ImageRestoreRequest(BaseModel):
    output_dir: str
    confirm: str
    safety_token: str


class ImageRestoreResult(BaseModel):
    output_dir: str
    status: str
    errors: list[str]
