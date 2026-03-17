import base64
import binascii
import mimetypes

from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.responses import FileResponse

from app.config import settings
from app.models import User
from app.schemas import (
    ImageDirectUploadRequest,
    ImageDirectUploadResponse,
    ImageUploadPrepareRequest,
    ImageUploadPrepareResponse,
)
from app.security import get_current_user
from app.services.storage import LocalStorageService, get_storage_service

router = APIRouter(prefix='/uploads', tags=['uploads'])


def _allowed_content_types() -> set[str]:
    return {
        content_type.strip().lower()
        for content_type in settings.upload_allowed_content_types.split(',')
        if content_type.strip()
    }


@router.post('/presign-image', response_model=ImageUploadPrepareResponse, status_code=status.HTTP_201_CREATED)
def presign_image_upload(
    payload: ImageUploadPrepareRequest,
    current_user: User = Depends(get_current_user),
) -> ImageUploadPrepareResponse:
    allowed = _allowed_content_types()
    if payload.content_type not in allowed:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Unsupported content_type for image upload.',
        )

    try:
        storage = get_storage_service()
    except RuntimeError as error:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(error),
        ) from error
    if isinstance(storage, LocalStorageService):
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail='Presigned upload is disabled for local storage mode. Use /uploads/image-direct.',
        )

    prepared = storage.prepare_image_upload(
        user_id=str(current_user.id),
        content_type=payload.content_type,
        file_extension=payload.file_extension,
    )
    return ImageUploadPrepareResponse(
        upload_url=prepared.upload_url,
        image_url=prepared.image_url,
        image_object_key=prepared.image_object_key,
        expires_in_seconds=prepared.expires_in_seconds,
        required_headers=prepared.required_headers,
    )


@router.post('/image-direct', response_model=ImageDirectUploadResponse, status_code=status.HTTP_201_CREATED)
def upload_image_direct(
    payload: ImageDirectUploadRequest,
    request: Request,
    current_user: User = Depends(get_current_user),
) -> ImageDirectUploadResponse:
    allowed = _allowed_content_types()
    if payload.content_type not in allowed:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Unsupported content_type for image upload.',
        )

    try:
        raw = base64.b64decode(payload.data_base64, validate=True)
    except (binascii.Error, ValueError) as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Invalid base64 payload for image upload.',
        ) from error

    if not raw:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Uploaded image payload is empty.',
        )

    if len(raw) > settings.upload_max_bytes:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f'Image exceeds max upload size of {settings.upload_max_bytes} bytes.',
        )

    storage = get_storage_service()
    stored = storage.store_image(
        user_id=str(current_user.id),
        content_type=payload.content_type,
        data=raw,
        file_extension=payload.file_extension,
    )

    image_url = stored.image_url
    if image_url.startswith('/'):
        image_url = f'{str(request.base_url).rstrip("/")}{image_url}'

    return ImageDirectUploadResponse(
        image_url=image_url,
        image_object_key=stored.image_object_key,
    )


@router.get('/files/{object_key:path}')
def get_uploaded_image(object_key: str):
    storage = get_storage_service()
    if not isinstance(storage, LocalStorageService):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Local upload file route is unavailable.',
        )

    try:
        file_path = storage.resolve_object_path(object_key)
    except RuntimeError as error:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(error),
        ) from error

    if not file_path.exists():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Uploaded file not found.',
        )

    media_type, _ = mimetypes.guess_type(str(file_path))
    return FileResponse(
        path=file_path,
        media_type=media_type or 'application/octet-stream',
    )
