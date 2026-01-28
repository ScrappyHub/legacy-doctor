from pydantic import BaseModel

class Device(BaseModel):
    id: str
    mount: str
    fstype: str | None
    total_bytes: int
    used_bytes: int
    free_bytes: int
    percent_used: float
    type: str  # UMS_GENERIC | IPOD_LEGACY | UNKNOWN
