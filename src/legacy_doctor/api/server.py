from fastapi import FastAPI
from legacy_doctor.api.routes import router

app = FastAPI(title="Legacy Doctor Backend", version="0.0.1")
app.include_router(router, prefix="/v1")