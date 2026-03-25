"""Application configuration using pydantic-settings."""

import json as _json
from functools import lru_cache

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Global application settings loaded from environment variables."""

    app_name: str = "Abyssal Descent AI Server"
    app_version: str = "0.1.0"
    debug: bool = False

    # Server
    host: str = "0.0.0.0"
    port: int = 8000

    # Redis
    redis_url: str = "redis://localhost:6379/0"
    redis_ttl_seconds: int = 3600

    # PostgreSQL
    database_url: str = "postgresql+asyncpg://abyssal:abyssal_secret@localhost:5432/abyssal_descent"

    # ChromaDB
    chromadb_host: str = "localhost"
    chromadb_port: int = 8001

    # CORS — stored as a plain string to avoid pydantic-settings JSON parse issues.
    cors_origins: str = '["http://localhost:8080","http://localhost:6060","http://127.0.0.1:8080","http://127.0.0.1:6060","http://localhost:8000","http://127.0.0.1:8000"]'

    # AI / LLM (Claude API)
    anthropic_api_key: str = ""
    llm_model: str = "claude-sonnet-4-20250514"
    llm_temperature: float = 0.8
    llm_max_tokens: int = 512
    llm_enabled: bool = True

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}

    def get_cors_origins(self) -> list[str]:
        """Parse cors_origins string into a list."""
        val = self.cors_origins.strip()
        if not val:
            return ["*"]
        try:
            result = _json.loads(val)
            if isinstance(result, list):
                return result
        except (_json.JSONDecodeError, TypeError):
            pass
        return [s.strip() for s in val.split(",") if s.strip()]


@lru_cache
def get_settings() -> Settings:
    """Return cached settings singleton."""
    return Settings()
