from pydantic import BaseModel, Field

class EjectResult(BaseModel):
    drive_letter: str
    disk_number: int | None = None
    status: str  # "ejected" | "failed"
    method: str | None = None
    warnings: list[str] = Field(default_factory=list)
    error: str | None = None
    raw: str | None = None
