from __future__ import annotations

from pydantic import BaseModel, Field
from typing import Literal


WipeMethod = Literal["quick_format", "full_format"]


class WipePlanResult(BaseModel):
    drive_letter: str
    method: WipeMethod
    disk_number: int
    is_system_disk: bool
    is_boot_disk: bool
    bus_type: str | None = None
    size_bytes: int | None = None
    safety_token: str
    warnings: list[str]
    recommended_steps: list[str]


class WipeRunRequest(BaseModel):
    method: WipeMethod
    confirm: str = Field(..., description="Must equal I_UNDERSTAND_THIS_WILL_ERASE_DATA")
    safety_token: str
    filesystem: str = Field(default="exFAT", description="exFAT|FAT32|NTFS (Windows Format-Volume)")
    new_label: str | None = None


class WipeRunResult(BaseModel):
    drive_letter: str
    method: WipeMethod
    ran: bool
    needs_admin: bool
    output_tail: list[str]
