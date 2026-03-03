from __future__ import annotations

from pydantic import BaseModel, Field
from typing import Any


class DoctorUsbResult(BaseModel):
    drive_letter: str
    volume: dict[str, Any] | None
    partition: dict[str, Any] | None
    disk: dict[str, Any] | None
    warnings: list[str]

    # optional artifact outputs
    wrote_report: bool = False
    report_path: str | None = None
    report_sha256_path: str | None = None


class DoctorUsbRequest(BaseModel):
    write_report: bool = Field(default=True, description="If true, writes report.json + report.json.sha256 into the job root")
    job_root: str | None = Field(default=None, description="If provided, write artifacts here; otherwise uses default data dir")
