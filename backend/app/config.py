from functools import lru_cache
from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


ROOT_DIR = Path(__file__).resolve().parents[2]


class Settings(BaseSettings):
    app_name: str = "赛智荐"
    debug: bool = True
    database_url: str = "postgresql+psycopg://saizhijian:saizhijian@127.0.0.1:5433/saizhijian"
    jwt_secret: str = Field(default="development-only-change-me", min_length=16)
    jwt_expire_hours: int = 168
    encryption_key: str = ""
    competition_db_path: Path = ROOT_DIR / "saikr_competitions.db"
    embedding_model_path: Path = ROOT_DIR / "models" / "bge-small-zh-v1.5"
    qdrant_url: str = "http://localhost:6333"
    qdrant_collection: str = "competitions_bge_small_zh_v15"
    frontend_build_path: Path = ROOT_DIR / "frontend" / "build" / "web"
    cors_origins: str = "http://localhost:8080,http://127.0.0.1:8080,http://[::1]:8080"

    model_config = SettingsConfigDict(
        env_file=(ROOT_DIR / ".env", ROOT_DIR / "backend" / ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    @property
    def cors_origin_list(self) -> list[str]:
        return [item.strip() for item in self.cors_origins.split(",") if item.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
