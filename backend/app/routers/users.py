from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import User
from app.security import get_current_user, hash_password
from app.schemas import UserCreate, UserRead
from app.services.users import allocate_tag, parse_handle, username_key

router = APIRouter(prefix='/users', tags=['users'])


@router.post('', response_model=UserRead, status_code=status.HTTP_201_CREATED)
def create_user(payload: UserCreate, db: Session = Depends(get_db)) -> User:
    normalized_username = payload.username.strip()
    key = username_key(normalized_username)
    tag = allocate_tag(db, key)

    user = User(
        username=normalized_username,
        username_key=key,
        tag=tag,
        display_name=payload.display_name.strip() if payload.display_name else None,
        password_hash=hash_password(payload.password) if payload.password else None,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@router.get('', response_model=list[UserRead])
def list_all_users(
    limit: int = Query(default=200, ge=1, le=1000),
    offset: int = Query(default=0, ge=0, le=100000),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[User]:
    if not current_user.is_platform_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Platform admin only.')

    users = db.scalars(
        select(User)
        .order_by(User.created_at.desc())
        .offset(offset)
        .limit(limit)
    ).all()
    return list(users)


@router.get('/lookup', response_model=UserRead)
def lookup_user_by_handle(
    handle: str = Query(..., description='Discord-style handle. Example: tony#0001'),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> User:
    key, tag = parse_handle(handle)

    user = db.scalar(select(User).where(User.username_key == key, User.tag == tag))
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found.')
    if user.is_platform_admin and not current_user.is_platform_admin:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found.')

    return user


@router.get('/{user_id}', response_model=UserRead)
def get_user(
    user_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> User:
    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found.')
    if user.is_platform_admin and not current_user.is_platform_admin:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='User not found.')
    return user
