import secrets

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import User


def username_key(username: str) -> str:
    return username.strip().lower()


def allocate_tag(db: Session, normalized_username_key: str) -> int:
    used_tags = set(
        db.scalars(select(User.tag).where(User.username_key == normalized_username_key)).all()
    )

    for candidate in range(1, 10000):
        if candidate not in used_tags:
            return candidate

    raise HTTPException(
        status_code=status.HTTP_409_CONFLICT,
        detail='No tags left for this username. Choose a different username.',
    )


def allocate_register_tag(
    db: Session,
    normalized_username_key: str,
    preferred_tag: int | None = None,
) -> int:
    used_tags = set(
        db.scalars(select(User.tag).where(User.username_key == normalized_username_key)).all()
    )

    if preferred_tag is not None and preferred_tag not in used_tags:
        return preferred_tag

    available_tags = [candidate for candidate in range(0, 10000) if candidate not in used_tags]
    if not available_tags:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail='No tags left for this username. Choose a different username.',
        )

    return secrets.choice(available_tags)


def parse_handle(raw_handle: str) -> tuple[str, int]:
    handle = raw_handle.strip()
    if '#' not in handle:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Invalid handle format. Use username#1234.',
        )

    name, tag_raw = handle.rsplit('#', 1)
    if len(tag_raw) != 4 or not tag_raw.isdigit():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Tag must be exactly 4 digits.',
        )

    normalized_key = username_key(name)
    if not normalized_key:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Handle username cannot be empty.',
        )

    return normalized_key, int(tag_raw)
