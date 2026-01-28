from fastapi import APIRouter
from legacy_doctor.core.devices import list_devices

router = APIRouter()

@router.get("/health")
def health():
    return {"status": "ok", "service": "legacy-doctor"}


@router.get("/devices")
def devices():
    return list_devices()
