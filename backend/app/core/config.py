from functools import lru_cache
from typing import Annotated
from zoneinfo import ZoneInfo

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    environment: str = "development"
    database_url: str
    secret_key: str = Field(min_length=32)
    access_token_minutes: int = Field(default=720, gt=0)
    timezone: str = "Asia/Jakarta"
    # NoDecode: nilai env dibaca apa adanya ("a,b" atau kosong), bukan sebagai JSON.
    cors_origins: Annotated[list[str], NoDecode] = []

    face_match_threshold: float = Field(default=0.8, gt=0, le=1)
    face_max_photos_per_student: int = Field(default=5, gt=0)
    max_upload_bytes: int = Field(default=5 * 1024 * 1024, gt=0)

    # Gambar konten website yang diunggah admin; disajikan di /media.
    media_dir: str = "uploads"
    max_media_bytes: int = Field(default=5 * 1024 * 1024, gt=0)

    # Domain email untuk akun orang tua yang dibuat otomatis saat admin menambah siswa.
    parent_email_domain: str = "ortu.sdn02pakunden.sch.id"

    @field_validator("cors_origins", mode="before")
    @classmethod
    def _split_origins(cls, value: object) -> object:
        if isinstance(value, str):
            return [v.strip() for v in value.split(",") if v.strip()]
        return value

    @property
    def is_production(self) -> bool:
        return self.environment.lower() == "production"

    @property
    def tzinfo(self) -> ZoneInfo:
        return ZoneInfo(self.timezone)


@lru_cache
def get_settings() -> Settings:
    return Settings()  # type: ignore[call-arg]
