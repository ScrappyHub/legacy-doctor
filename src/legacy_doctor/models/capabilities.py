from pydantic import BaseModel, Field

class DeviceCapabilities(BaseModel):
    drive_letter: str
    mount: str

    # Identity
    disk_number: int | None = None
    disk_friendly_name: str | None = None
    bus_type: str | None = None

    # Current state
    filesystem: str | None = None
    volume_label: str | None = None
    size_bytes: int | None = None
    size_remaining_bytes: int | None = None
    health_status: str | None = None
    operational_status: list[str] = Field(default_factory=list)

    # Doctor policy
    allowed_filesystems: list[str] = Field(default_factory=list)
    warnings: list[str] = Field(default_factory=list)


class RenameRequest(BaseModel):
    new_label: str


class RenameResult(BaseModel):
    drive_letter: str
    old_label: str | None
    new_label: str