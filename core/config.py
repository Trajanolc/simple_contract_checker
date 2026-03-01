from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8")

    openai_api_key: str | None = None
    openai_model: str = "gpt-4.1-mini"
    max_doc_chars: int = 150_000
    max_findings: int = 20


settings = Settings()  # type: ignore[call-arg]
