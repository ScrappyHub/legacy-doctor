from __future__ import annotations

from fastapi import FastAPI
from legacy_doctor.api.routes import router

app = FastAPI(title="legacy-doctor", version="0.2.0")
app.include_router(router, prefix="/v1")
