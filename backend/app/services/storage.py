import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import boto3
from botocore.config import Config

from app.config import settings


@dataclass
class PreparedImageUpload:
    upload_url: str
    image_url: str
    image_object_key: str
    expires_in_seconds: int
    required_headers: dict[str, str]


@dataclass
class StoredImage:
    image_url: str
    image_object_key: str


class S3StorageService:
    def __init__(self) -> None:
        if not settings.s3_endpoint_url:
            raise RuntimeError('S3 endpoint is not configured.')
        if not settings.s3_access_key_id or not settings.s3_secret_access_key:
            raise RuntimeError('S3 credentials are not configured.')

        self._client = boto3.client(
            's3',
            endpoint_url=settings.s3_endpoint_url,
            region_name=settings.s3_region,
            aws_access_key_id=settings.s3_access_key_id,
            aws_secret_access_key=settings.s3_secret_access_key,
            config=Config(
                signature_version='s3v4',
                s3={'addressing_style': 'path' if settings.s3_use_path_style else 'virtual'},
            ),
        )

    def prepare_image_upload(
        self,
        *,
        user_id: str,
        content_type: str,
        file_extension: str | None = None,
    ) -> PreparedImageUpload:
        key = self._generate_object_key(
            user_id=user_id,
            content_type=content_type,
            file_extension=file_extension,
        )

        upload_url = self._client.generate_presigned_url(
            ClientMethod='put_object',
            Params={
                'Bucket': settings.s3_bucket,
                'Key': key,
                'ContentType': content_type,
            },
            ExpiresIn=settings.s3_presign_expiry_seconds,
        )

        return PreparedImageUpload(
            upload_url=upload_url,
            image_url=self._public_url_for_key(key),
            image_object_key=key,
            expires_in_seconds=settings.s3_presign_expiry_seconds,
            required_headers={'Content-Type': content_type},
        )

    def store_image(
        self,
        *,
        user_id: str,
        content_type: str,
        data: bytes,
        file_extension: str | None = None,
    ) -> StoredImage:
        key = self._generate_object_key(
            user_id=user_id,
            content_type=content_type,
            file_extension=file_extension,
        )
        self._client.put_object(
            Bucket=settings.s3_bucket,
            Key=key,
            Body=data,
            ContentType=content_type,
        )
        return StoredImage(
            image_url=self._public_url_for_key(key),
            image_object_key=key,
        )

    def delete_object(self, object_key: str) -> None:
        self._client.delete_object(
            Bucket=settings.s3_bucket,
            Key=object_key,
        )

    def _generate_object_key(
        self,
        *,
        user_id: str,
        content_type: str,
        file_extension: str | None = None,
    ) -> str:
        extension = (file_extension or self._guess_extension(content_type)).lower()
        timestamp = datetime.now(timezone.utc)
        return (
            f'{settings.s3_prefix.strip("/")}/'
            f'{timestamp:%Y/%m/%d}/{user_id}/{uuid.uuid4().hex}.{extension}'
        )

    def _public_url_for_key(self, key: str) -> str:
        if settings.s3_public_base_url:
            return f'{settings.s3_public_base_url.rstrip("/")}/{key}'

        endpoint = settings.s3_endpoint_url or ''
        if settings.s3_use_path_style:
            return f'{endpoint.rstrip("/")}/{settings.s3_bucket}/{key}'
        return f'{endpoint.rstrip("/")}/{key}'

    def _guess_extension(self, content_type: str) -> str:
        if content_type == 'image/jpeg':
            return 'jpg'
        if content_type == 'image/png':
            return 'png'
        if content_type == 'image/webp':
            return 'webp'
        if content_type == 'image/gif':
            return 'gif'
        return 'bin'


class LocalStorageService:
    def __init__(self) -> None:
        self._root = Path(settings.local_upload_dir).resolve()
        self._root.mkdir(parents=True, exist_ok=True)

    def store_image(
        self,
        *,
        user_id: str,
        content_type: str,
        data: bytes,
        file_extension: str | None = None,
    ) -> StoredImage:
        extension = (file_extension or self._guess_extension(content_type)).lower()
        timestamp = datetime.now(timezone.utc)
        key = (
            f'local/{timestamp:%Y/%m/%d}/{user_id}/{uuid.uuid4().hex}.{extension}'
        )
        file_path = self.resolve_object_path(key)
        file_path.parent.mkdir(parents=True, exist_ok=True)
        file_path.write_bytes(data)

        return StoredImage(
            image_url=f'{settings.api_prefix}/uploads/files/{key}',
            image_object_key=key,
        )

    def delete_object(self, object_key: str) -> None:
        file_path = self.resolve_object_path(object_key)
        if file_path.exists():
            file_path.unlink()

    def resolve_object_path(self, object_key: str) -> Path:
        normalized_key = object_key.strip().replace('\\', '/').lstrip('/')
        resolved = (self._root / normalized_key).resolve()
        if not str(resolved).startswith(str(self._root)):
            raise RuntimeError('Invalid local object key path.')
        return resolved

    def _guess_extension(self, content_type: str) -> str:
        if content_type == 'image/jpeg':
            return 'jpg'
        if content_type == 'image/png':
            return 'png'
        if content_type == 'image/webp':
            return 'webp'
        if content_type == 'image/gif':
            return 'gif'
        return 'bin'


def get_storage_service() -> S3StorageService | LocalStorageService:
    if settings.s3_endpoint_url and settings.s3_access_key_id and settings.s3_secret_access_key:
        return S3StorageService()
    return LocalStorageService()
