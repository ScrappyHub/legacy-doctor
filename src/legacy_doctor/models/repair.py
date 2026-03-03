from __future__ import annotations

from pydantic import BaseModel, Field
from typing import Literal


class ChkdskRequest(BaseModel):
    mode: Literal["dry_run", "run"] = "dry_run"
    confirm: str | None = Field(default=None, description="Required when mode=run")
    write_report: bool = Field(default=True, description="If true, writes repair_report.json + sha256 into job_root")
    job_root: str | None = Field(default=None, description="If provided, write artifacts here; otherwise default data dir")


class ChkdskResult(BaseModel):
    drive_letter: str
    mode: str
    ran: bool
    needs_admin: bool
    command: str
    output_tail: list[str]

    wrote_report: bool = False
    report_path: str | None = None
    report_sha256_path: str | None = None
