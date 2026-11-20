from contextlib import asynccontextmanager
from datetime import datetime
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text
from starlette.exceptions import HTTPException as StarletteHTTPException

from app.api.routers import api_router
from app.core.config import Settings, get_settings
from app.core.database import build_engine, build_session_factory
from app.core.errors import AppError
from app.services.media_service import MEDIA_URL_PREFIX
from app.services.ml_service import FaceEmbedder, MockFaceEmbedder

API_PREFIX = "/api/v1"

_HTTP_MESSAGES = {
    404: "Data tidak ditemukan.",
    405: "Metode tidak diizinkan.",
    413: "Ukuran data terlalu besar.",
}


class SafeStaticFiles(StaticFiles):
    """File media hanya gambar; nosniff mencegah browser menebak tipe lain dari isinya."""

    async def get_response(self, path, scope):
        response = await super().get_response(path, scope)
        response.headers["X-Content-Type-Options"] = "nosniff"
        return response


def create_app(
    settings: Settings | None = None,
    *,
    embedder: FaceEmbedder | None = None,
) -> FastAPI:
    settings = settings or get_settings()
    engine = build_engine(settings.database_url)

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        yield
        engine.dispose()

    app = FastAPI(
        title="API SDN 02 Pakunden",
        version="0.1.0",
        lifespan=lifespan,
        docs_url=None if settings.is_production else "/docs",
        redoc_url=None,
        openapi_url=None if settings.is_production else "/openapi.json",
    )
    app.state.settings = settings
    app.state.session_factory = build_session_factory(engine)
    app.state.clock = lambda: datetime.now(settings.tzinfo)
    app.state.embedder = embedder or MockFaceEmbedder()

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_origin_regex=None if settings.is_production else r"http://(localhost|127\.0\.0\.1)(:\d+)?",
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
        allow_headers=["Authorization", "Content-Type", "Accept"],
    )

    @app.exception_handler(AppError)
    async def _app_error(_: Request, exc: AppError) -> JSONResponse:
        return JSONResponse(exc.body(), status_code=exc.status_code)

    @app.exception_handler(StarletteHTTPException)
    async def _http_error(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        message = _HTTP_MESSAGES.get(exc.status_code) or (
            exc.detail if isinstance(exc.detail, str) else "Terjadi kesalahan."
        )
        return JSONResponse({"message": message}, status_code=exc.status_code, headers=exc.headers)

    @app.exception_handler(RequestValidationError)
    async def _validation_error(_: Request, exc: RequestValidationError) -> JSONResponse:
        errors: dict[str, str] = {}
        for item in exc.errors():
            field = str(item["loc"][-1]) if item["loc"] else "body"
            if item["type"] == "missing":
                message = "Kolom ini wajib diisi."
            elif item["type"] == "value_error":
                # Pesan dari validator buatan sendiri sudah berbahasa Indonesia dan siap ditampilkan.
                message = str(item["ctx"]["error"])
            else:
                message = "Nilai tidak valid."
            errors.setdefault(field, message)
        return JSONResponse(
            {"message": "Data yang dikirim tidak valid.", "errors": errors}, status_code=422
        )

    @app.get("/health", tags=["system"])
    def health() -> JSONResponse:
        try:
            with engine.connect() as connection:
                connection.execute(text("SELECT 1"))
        except Exception:
            return JSONResponse({"status": "database_unavailable"}, status_code=503)
        return JSONResponse({"status": "ok"})

    app.include_router(api_router, prefix=API_PREFIX)

    media_dir = Path(settings.media_dir)
    media_dir.mkdir(parents=True, exist_ok=True)
    app.mount(MEDIA_URL_PREFIX, SafeStaticFiles(directory=media_dir), name="media")
    return app
