from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    # Supports running uvicorn from either backend/ (finds the repo-root .env
    # via ../.env) or from the repo root (finds ./backend/.env or ./.env).
    model_config = SettingsConfigDict(env_file=(".env", "../.env"), extra="ignore")

    openrouter_api_key: str
    openrouter_model: str = "anthropic/claude-haiku-4.5"
    openrouter_site_url: str = "http://localhost"
    openrouter_site_name: str = "My OpenRouter Chatbot"
    openrouter_base_url: str = "https://openrouter.ai/api/v1"

    app_shared_secret: str = ""
    cors_origins: str = "http://localhost:3000"

    @property
    def cors_origin_list(self) -> list[str]:
        return [origin.strip() for origin in self.cors_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
