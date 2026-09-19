from functools import lru_cache
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")
    database_url: str = "sqlite:///./embervale.local.db"
    jwt_secret: str = "local-development-secret"
    jwt_previous_secret: str = ""
    oidc_issuer: str = ""
    oidc_audience: str = ""
    oidc_jwks_url: str = ""
    jwt_ttl_seconds: int = 3600
    environment: str = "development"
    allowed_origins: str = "http://localhost:3000"
    revenuecat_api_key: str = ""
    revenuecat_webhook_secret: str = ""
    # Low-privilege token the shipped game client presents on the read-only
    # entitlements route. It can only read the named customer's entitlements;
    # the provider secret never leaves the server.
    store_app_token: str = ""
    stripe_secret_key: str = ""
    stripe_webhook_secret: str = ""
    stripe_success_url: str = "https://example.invalid/checkout/success"
    stripe_cancel_url: str = "https://example.invalid/checkout/cancel"
    stripe_alternative_billing_enabled: bool = False
    max_sync_batch: int = 32
    max_request_bytes: int = 131072
    rate_limit_per_minute: int = 60
    docs_enabled: bool = False

    @property
    def origins(self) -> list[str]:
        return [origin.strip() for origin in self.allowed_origins.split(",") if origin.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
