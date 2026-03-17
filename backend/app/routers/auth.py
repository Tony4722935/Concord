import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.models import Channel, ChannelMember, Message, RefreshToken, Server, User
from app.schemas import (
    AuthLogin,
    AuthRegister,
    AuthSession,
    AuthTokens,
    ImageAssetUpdate,
    RefreshRequest,
    UserDeleteRequest,
    UserRead,
    UserSettingsUpdate,
)
from app.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    get_current_user,
    hash_password,
    verify_password,
)
from app.services.users import allocate_register_tag, allocate_tag, parse_handle, username_key
from app.services.media import collect_message_object_keys, delete_storage_objects, resolve_storage_object_key

router = APIRouter(prefix='/auth', tags=['auth'])


def _issue_tokens(db: Session, user: User) -> AuthTokens:
    refresh_expires_at = datetime.now(timezone.utc) + timedelta(days=settings.refresh_token_days)
    refresh_row = RefreshToken(user_id=user.id, expires_at=refresh_expires_at)
    db.add(refresh_row)
    db.flush()

    access_token = create_access_token(user_id=user.id)
    refresh_token = create_refresh_token(
        user_id=user.id,
        token_id=refresh_row.id,
        expires_at=refresh_expires_at,
    )

    return AuthTokens(
        access_token=access_token,
        refresh_token=refresh_token,
        access_expires_in_seconds=settings.access_token_minutes * 60,
    )


def _session(user: User, tokens: AuthTokens) -> AuthSession:
    return AuthSession(
        user=UserRead.model_validate(user),
        tokens=tokens,
    )


@router.post('/register', response_model=AuthSession, status_code=status.HTTP_201_CREATED)
def register(payload: AuthRegister, db: Session = Depends(get_db)) -> AuthSession:
    normalized_username = payload.username.strip()
    key = username_key(normalized_username)
    tag = allocate_register_tag(
        db=db,
        normalized_username_key=key,
        preferred_tag=payload.preferred_tag,
    )

    user = User(
        username=normalized_username,
        username_key=key,
        tag=tag,
        display_name=payload.display_name.strip() if payload.display_name else None,
        password_hash=hash_password(payload.password),
    )

    db.add(user)
    db.flush()

    tokens = _issue_tokens(db, user)
    db.commit()
    db.refresh(user)

    return _session(user, tokens)


@router.post('/login', response_model=AuthSession)
def login(payload: AuthLogin, db: Session = Depends(get_db)) -> AuthSession:
    identifier = payload.identifier.strip()

    user: User | None = None

    if '#' in identifier:
        key, tag = parse_handle(identifier)
        user = db.scalar(select(User).where(User.username_key == key, User.tag == tag))
    else:
        key = username_key(identifier)
        matches = db.scalars(select(User).where(User.username_key == key)).all()
        if len(matches) > 1:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail='Multiple users found for username. Use full handle like name#1234.',
            )
        if matches:
            user = matches[0]

    if user is None or not user.password_hash or not verify_password(payload.password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid credentials.')

    tokens = _issue_tokens(db, user)
    db.commit()

    return _session(user, tokens)


@router.post('/refresh', response_model=AuthTokens)
def refresh_tokens(payload: RefreshRequest, db: Session = Depends(get_db)) -> AuthTokens:
    decoded = decode_token(payload.refresh_token, expected_type='refresh')

    subject = decoded.get('sub')
    token_id_raw = decoded.get('jti')
    if not subject or not token_id_raw:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid refresh token.')

    try:
        user_id = uuid.UUID(subject)
        token_id = uuid.UUID(token_id_raw)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Invalid refresh token.') from exc

    row = db.get(RefreshToken, token_id)
    now = datetime.now(timezone.utc)

    if row is None or row.user_id != user_id or row.revoked_at is not None or row.expires_at <= now:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='Refresh token is not valid.')

    user = db.get(User, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail='User not found.')

    row.revoked_at = now
    tokens = _issue_tokens(db, user)
    db.commit()

    return tokens


@router.get('/me', response_model=UserRead)
def me(current_user: User = Depends(get_current_user)) -> User:
    return current_user


@router.patch('/me', response_model=UserRead)
def update_me(
    payload: UserSettingsUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> User:
    changed = False

    if 'display_name' in payload.model_fields_set:
        current_user.display_name = payload.display_name
        changed = True

    if 'theme_preference' in payload.model_fields_set and payload.theme_preference is not None:
        if current_user.theme_preference != payload.theme_preference:
            current_user.theme_preference = payload.theme_preference
            changed = True

    if 'language' in payload.model_fields_set and payload.language is not None:
        if current_user.language != payload.language:
            current_user.language = payload.language
            changed = True

    if 'time_format' in payload.model_fields_set and payload.time_format is not None:
        if current_user.time_format != payload.time_format:
            current_user.time_format = payload.time_format
            changed = True

    if 'compact_mode' in payload.model_fields_set and payload.compact_mode is not None:
        if current_user.compact_mode != payload.compact_mode:
            current_user.compact_mode = payload.compact_mode
            changed = True

    if (
        'show_message_timestamps' in payload.model_fields_set
        and payload.show_message_timestamps is not None
    ):
        if current_user.show_message_timestamps != payload.show_message_timestamps:
            current_user.show_message_timestamps = payload.show_message_timestamps
            changed = True

    if 'username' in payload.model_fields_set and payload.username is not None:
        normalized_username = payload.username.strip()
        key = username_key(normalized_username)

        if key != current_user.username_key:
            current_user.username_key = key
            current_user.tag = allocate_tag(db, key)

        if current_user.username != normalized_username:
            current_user.username = normalized_username

        changed = True

    if payload.new_password is not None:
        if current_user.password_hash is None:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail='Password login is not enabled for this account.',
            )

        if payload.current_password is None or not verify_password(
            payload.current_password,
            current_user.password_hash,
        ):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail='Current password is incorrect.',
            )

        current_user.password_hash = hash_password(payload.new_password)
        changed = True

        now = datetime.now(timezone.utc)
        active_refresh_tokens = db.scalars(
            select(RefreshToken).where(
                RefreshToken.user_id == current_user.id,
                RefreshToken.revoked_at.is_(None),
                RefreshToken.expires_at > now,
            )
        ).all()
        for token in active_refresh_tokens:
            token.revoked_at = now

    if changed:
        db.commit()
        db.refresh(current_user)

    return current_user


@router.put('/me/avatar', response_model=UserRead)
def update_my_avatar(
    payload: ImageAssetUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> User:
    previous_key = resolve_storage_object_key(
        current_user.avatar_object_key,
        current_user.avatar_url,
    )
    next_key = resolve_storage_object_key(payload.image_object_key, payload.image_url)

    current_user.avatar_url = payload.image_url
    current_user.avatar_object_key = payload.image_object_key
    db.commit()
    db.refresh(current_user)

    if previous_key and previous_key != next_key:
        try:
            delete_storage_objects([previous_key])
        except Exception:
            # Best effort cleanup when replacing avatar image.
            pass

    return current_user


@router.delete('/me/avatar', response_model=UserRead)
def clear_my_avatar(
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> User:
    previous_key = resolve_storage_object_key(
        current_user.avatar_object_key,
        current_user.avatar_url,
    )
    current_user.avatar_url = None
    current_user.avatar_object_key = None
    db.commit()
    db.refresh(current_user)

    if previous_key:
        try:
            delete_storage_objects([previous_key])
        except Exception:
            # Best effort cleanup when clearing avatar image.
            pass

    return current_user


@router.delete('/me', status_code=status.HTTP_204_NO_CONTENT)
def delete_me(
    payload: UserDeleteRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    if current_user.is_platform_admin:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Platform admin account cannot be deleted from user settings.',
        )

    if current_user.password_hash is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Password login is not enabled for this account.',
        )

    if not verify_password(payload.current_password, current_user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Current password is incorrect.',
        )

    owned_server_count = db.scalar(
        select(func.count(Server.id)).where(Server.owner_user_id == current_user.id)
    ) or 0
    if owned_server_count > 0:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail='Transfer ownership or delete your owned servers before deleting your account.',
        )

    dm_channel_ids = db.scalars(
        select(Channel.id)
        .join(ChannelMember, ChannelMember.channel_id == Channel.id)
        .where(
            Channel.kind == 'dm',
            Channel.server_id.is_(None),
            ChannelMember.user_id == current_user.id,
        )
    ).all()

    message_rows = db.execute(
        select(Message.image_object_key, Message.image_url).where(
            Message.author_user_id == current_user.id,
            or_(Message.image_object_key.is_not(None), Message.image_url.is_not(None)),
        )
    ).all()
    object_keys = collect_message_object_keys(message_rows)
    avatar_object_key = resolve_storage_object_key(
        current_user.avatar_object_key,
        current_user.avatar_url,
    )
    if avatar_object_key:
        object_keys.add(avatar_object_key)

    if dm_channel_ids:
        dm_message_rows = db.execute(
            select(Message.image_object_key, Message.image_url).where(
                Message.channel_id.in_(dm_channel_ids),
                or_(Message.image_object_key.is_not(None), Message.image_url.is_not(None)),
            )
        ).all()
        object_keys.update(collect_message_object_keys(dm_message_rows))

    if object_keys:
        try:
            delete_storage_objects(object_keys)
        except RuntimeError as error:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=f'Unable to delete account uploads: {error}',
            ) from error
        except Exception as error:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail='Failed to delete one or more account uploads.',
            ) from error

    if dm_channel_ids:
        dm_channels = db.scalars(select(Channel).where(Channel.id.in_(dm_channel_ids))).all()
        for channel in dm_channels:
            db.delete(channel)

    db.delete(current_user)
    db.commit()
    return None
