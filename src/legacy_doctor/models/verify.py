from __future__ import annotations

from pydantic import BaseModel, Field
from typing import Any


class VerifyRequest(BaseModel):
    job_root: str = Field(..., description="Path to job root folder containing manifest.json, sha256sums.txt, etc.")


class VerifyResult(BaseModel):
    job_root: str
    status: str
    checks: dict[str, Any]
    mismatches: list[Any]
    missing: list[str]
    notes: list[str]
    stats: dict[str, Any] | None = None
