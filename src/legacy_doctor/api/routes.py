from __future__ import annotations

from fastapi import APIRouter, HTTPException

# core
from legacy_doctor.core.winprobe import list_devices
from legacy_doctor.core.export_engine import export_plan, export_run
from legacy_doctor.core.library_engine import index_library, restore_library

from legacy_doctor.core.doctor_engine import doctor_usb, doctor_usb_and_write
from legacy_doctor.core.repair_engine import run_chkdsk, run_chkdsk_and_write
from legacy_doctor.core.wipe_engine import wipe_plan, wipe_run
from legacy_doctor.core.verify_engine import verify_job
from legacy_doctor.core.image_engine import image_plan, image_run

# models
from legacy_doctor.models.export import ExportPlan, ExportRunRequest, ExportRunResult
from legacy_doctor.models.library import (
    LibraryIndexRequest, LibraryIndexResult,
    LibraryRestoreRequest, LibraryRestoreResult
)
from legacy_doctor.models.doctor import DoctorUsbResult, DoctorUsbRequest
from legacy_doctor.models.repair import ChkdskRequest, ChkdskResult
from legacy_doctor.models.wipe import WipePlanResult, WipeRunRequest, WipeRunResult
from legacy_doctor.models.verify import VerifyRequest, VerifyResult
from legacy_doctor.models.image import ImagePlanResult, ImageRunRequest, ImageRunResult

router = APIRouter()


def _bad(msg: str):
    raise HTTPException(status_code=400, detail=msg)


@router.get("/health")
def health():
    return {"ok": True}


@router.get("/devices")
def devices():
    return list_devices()


# ----------------------------
# export
# ----------------------------

@router.get("/devices/{drive_letter}/export/plan", response_model=ExportPlan)
def device_export_plan(drive_letter: str, staging_dir: str | None = None):
    try:
        return export_plan(drive_letter, staging_dir=staging_dir)
    except ValueError as e:
        _bad(str(e))


@router.post("/devices/{drive_letter}/export/run", response_model=ExportRunResult)
def device_export_run(drive_letter: str, req: ExportRunRequest):
    try:
        return export_run(drive_letter, req)
    except ValueError as e:
        _bad(str(e))


# ----------------------------
# library
# ----------------------------

@router.post("/library/index", response_model=LibraryIndexResult)
def api_library_index(req: LibraryIndexRequest):
    try:
        return index_library(
            source_dir=req.source_dir,
            drive_letter=req.drive_letter,
            run_id=req.run_id,
        )
    except ValueError as e:
        _bad(str(e))


@router.post("/library/restore", response_model=LibraryRestoreResult)
def api_library_restore(req: LibraryRestoreRequest):
    try:
        return restore_library(
            manifest_path=req.manifest_path,
            source_dir=req.source_dir,
            target_root=req.target_root,
            mode=req.mode,
            overwrite=req.overwrite,
        )
    except ValueError as e:
        _bad(str(e))


@router.post("/library/verify", response_model=VerifyResult)
def api_library_verify(req: VerifyRequest):
    try:
        return verify_job(req.job_root)
    except ValueError as e:
        _bad(str(e))


# ----------------------------
# doctor
# ----------------------------

@router.get("/devices/{drive_letter}/doctor/usb", response_model=DoctorUsbResult)
def api_doctor_usb_get(drive_letter: str):
    try:
        return doctor_usb(drive_letter)
    except ValueError as e:
        _bad(str(e))


@router.post("/devices/{drive_letter}/doctor/usb", response_model=DoctorUsbResult)
def api_doctor_usb_post(drive_letter: str, req: DoctorUsbRequest):
    try:
        if req.write_report:
            return doctor_usb_and_write(drive_letter, job_root=req.job_root)
        return doctor_usb(drive_letter)
    except ValueError as e:
        _bad(str(e))


# ----------------------------
# repair
# ----------------------------

@router.post("/devices/{drive_letter}/repair/chkdsk", response_model=ChkdskResult)
def api_chkdsk(drive_letter: str, req: ChkdskRequest):
    try:
        if req.write_report:
            return run_chkdsk_and_write(drive_letter, mode=req.mode, confirm=req.confirm, job_root=req.job_root)
        return run_chkdsk(drive_letter, mode=req.mode, confirm=req.confirm)
    except ValueError as e:
        _bad(str(e))


# ----------------------------
# wipe
# ----------------------------

@router.get("/devices/{drive_letter}/wipe/plan", response_model=WipePlanResult)
def api_wipe_plan(drive_letter: str, method: str):
    try:
        return wipe_plan(drive_letter, method=method)
    except ValueError as e:
        _bad(str(e))


@router.post("/devices/{drive_letter}/wipe/run", response_model=WipeRunResult)
def api_wipe_run(drive_letter: str, req: WipeRunRequest):
    try:
        return wipe_run(drive_letter, req.model_dump())
    except ValueError as e:
        _bad(str(e))


# ----------------------------
# image (block imaging) - v1 skeleton
# ----------------------------

@router.get("/devices/{drive_letter}/image/plan", response_model=ImagePlanResult)
def api_image_plan(drive_letter: str, chunk_bytes: int = 8 * 1024 * 1024, output_dir: str | None = None):
    try:
        return image_plan(drive_letter, chunk_bytes=chunk_bytes, output_dir=output_dir)
    except ValueError as e:
        _bad(str(e))


@router.post("/devices/{drive_letter}/image/run", response_model=ImageRunResult)
def api_image_run(drive_letter: str, req: ImageRunRequest):
    try:
        return image_run(drive_letter, req.model_dump())
    except ValueError as e:
        _bad(str(e))
