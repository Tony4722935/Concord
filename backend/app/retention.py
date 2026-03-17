from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.config import settings
from app.models import Message
from app.services.storage import get_storage_service


@dataclass
class RetentionSummary:
    messages_deleted: int
    images_expired: int
    objects_deleted: int
    object_delete_failures: int


def run_retention_sweep(db: Session, now: datetime | None = None) -> RetentionSummary:
    current_time = now or datetime.now(timezone.utc)

    message_cutoff = current_time - timedelta(days=settings.message_retention_days)

    expired_images = db.scalars(
        select(Message).where(
            Message.image_url.is_not(None),
            Message.image_expires_at.is_not(None),
            Message.image_expires_at <= current_time,
        )
    ).all()

    storage = None
    try:
        storage = get_storage_service()
    except RuntimeError:
        storage = None

    objects_deleted = 0
    object_delete_failures = 0
    for message in expired_images:
        if message.image_object_key:
            if storage is not None:
                try:
                    storage.delete_object(message.image_object_key)
                    objects_deleted += 1
                except Exception:
                    object_delete_failures += 1
            else:
                object_delete_failures += 1

        message.image_url = None
        message.image_object_key = None
        if message.content is None:
            message.content = 'Image removed after 7 days.'

    delete_stmt = delete(Message).where(Message.created_at < message_cutoff)
    delete_result = db.execute(delete_stmt)

    db.commit()

    return RetentionSummary(
        messages_deleted=delete_result.rowcount or 0,
        images_expired=len(expired_images),
        objects_deleted=objects_deleted,
        object_delete_failures=object_delete_failures,
    )
