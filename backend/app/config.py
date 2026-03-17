from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file='.env',
        env_file_encoding='utf-8',
        extra='ignore',
    )

    app_name: str = 'Concord API'
    api_prefix: str = '/v1'
    database_url: str = 'postgresql+psycopg://concord:concord@localhost:5432/concord'
    cors_allow_origins: str = '*'
    jwt_secret: str = 'change-me-in-production'
    jwt_algorithm: str = 'HS256'
    access_token_minutes: int = 30
    refresh_token_days: int = 30
    message_retention_days: int = 365
    upload_retention_days: int = 7
    upload_max_bytes: int = 10 * 1024 * 1024
    retention_sweep_minutes: int = 60
    local_upload_dir: str = '/data/uploads'
    s3_endpoint_url: str | None = None
    s3_region: str = 'us-east-1'
    s3_access_key_id: str | None = None
    s3_secret_access_key: str | None = None
    s3_bucket: str = 'concord-images'
    s3_public_base_url: str | None = None
    s3_presign_expiry_seconds: int = 900
    s3_use_path_style: bool = True
    s3_prefix: str = 'images'
    upload_allowed_content_types: str = 'image/jpeg,image/png,image/webp,image/gif'


settings = Settings()
