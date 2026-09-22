from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache


def _flag(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _csv(name: str) -> tuple[str, ...]:
    return tuple(item.strip() for item in os.getenv(name, "").split(",") if item.strip())


@dataclass(frozen=True)
class Settings:
    environment: str
    require_auth: bool
    firebase_project_id: str | None
    check_revoked_tokens: bool
    allowed_origins: tuple[str, ...]
    allowed_hosts: tuple[str, ...]
    openai_api_key: str | None = None
    openai_model: str | None = None
    openai_timeout_seconds: float = 8.0

    @property
    def is_production(self) -> bool:
        return self.environment == "production"

    def validate(self) -> None:
        if self.is_production and not self.require_auth:
            raise RuntimeError("REQUIRE_AUTH cannot be disabled in production")
        if self.is_production and not self.firebase_project_id:
            raise RuntimeError("FIREBASE_PROJECT_ID is required in production")
        if self.is_production and not self.allowed_origins:
            raise RuntimeError("ALLOWED_ORIGINS is required in production")
        if self.is_production and not self.allowed_hosts:
            raise RuntimeError("ALLOWED_HOSTS is required in production")


@lru_cache
def get_settings() -> Settings:
    try:
        openai_timeout_seconds = float(os.getenv("OPENAI_TIMEOUT_SECONDS", "8"))
    except ValueError as exc:
        raise RuntimeError("OPENAI_TIMEOUT_SECONDS must be a number") from exc
    if openai_timeout_seconds <= 0:
        raise RuntimeError("OPENAI_TIMEOUT_SECONDS must be greater than zero")

    settings = Settings(
        environment=os.getenv("APP_ENV", "development").strip().lower(),
        require_auth=_flag("REQUIRE_AUTH", True),
        firebase_project_id=os.getenv("FIREBASE_PROJECT_ID") or None,
        check_revoked_tokens=_flag("CHECK_REVOKED_TOKENS", True),
        allowed_origins=_csv("ALLOWED_ORIGINS"),
        allowed_hosts=_csv("ALLOWED_HOSTS"),
        openai_api_key=os.getenv("OPENAI_API_KEY") or None,
        openai_model=os.getenv("OPENAI_MODEL") or None,
        openai_timeout_seconds=openai_timeout_seconds,
    )
    settings.validate()
    return settings
