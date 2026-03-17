from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.models import Channel, ChannelMember, Friendship, Message, User
from app.realtime import realtime_hub
from app.schemas import (
    DirectMessageChannelRead,
    DirectMessageCreate,
    DirectMessageMessageCreate,
    DirectMessageMessageEdit,
    DirectMessageMessageRead,
)
from app.security import get_current_user
from app.services.friends import friendship_pair

router = APIRouter(prefix='/dms', tags=['dms'])


def _ensure_friends(db: Session, user_a_id: UUID, user_b_id: UUID) -> None:
    low, high = friendship_pair(user_a_id, user_b_id)
    friendship = db.scalar(
        select(Friendship).where(Friendship.user_low_id == low, Friendship.user_high_id == high)
    )
    if friendship is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='You can only start DMs with friends.',
        )


def _find_dm_channel(db: Session, user_a_id: UUID, user_b_id: UUID) -> Channel | None:
    candidate_channel_ids = db.scalars(
        select(ChannelMember.channel_id)
        .join(Channel, Channel.id == ChannelMember.channel_id)
        .where(
            Channel.kind == 'dm',
            Channel.server_id.is_(None),
            ChannelMember.user_id == user_a_id,
        )
    ).all()

    for channel_id in candidate_channel_ids:
        member_ids = db.scalars(
            select(ChannelMember.user_id).where(ChannelMember.channel_id == channel_id)
        ).all()
        members = set(member_ids)
        if len(members) == 2 and user_a_id in members and user_b_id in members:
            return db.get(Channel, channel_id)

    return None


def _require_dm_membership(db: Session, channel_id: UUID, user_id: UUID) -> Channel:
    channel = db.get(Channel, channel_id)
    if channel is None or channel.kind != 'dm' or channel.server_id is not None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='DM channel not found.')

    membership = db.scalar(
        select(ChannelMember).where(ChannelMember.channel_id == channel_id, ChannelMember.user_id == user_id)
    )
    if membership is None:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='No access to this DM.')

    return channel


def _dm_channel_read(db: Session, channel: Channel, current_user_id: UUID) -> DirectMessageChannelRead:
    members = db.scalars(select(ChannelMember).where(ChannelMember.channel_id == channel.id)).all()
    peer_member = next((member for member in members if member.user_id != current_user_id), None)
    if peer_member is None:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Invalid DM channel state.')

    peer = db.get(User, peer_member.user_id)
    if peer is None:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Peer user missing.')

    return DirectMessageChannelRead(
        channel_id=channel.id,
        peer_user_id=peer.id,
        peer_handle=peer.handle,
        peer_display_name=peer.display_name,
        peer_avatar_url=peer.avatar_url,
    )


def _dm_message_read(message: Message) -> DirectMessageMessageRead:
    return DirectMessageMessageRead(
        message_id=message.id,
        channel_id=message.channel_id,
        author_user_id=message.author_user_id,
        content=message.content,
        image_url=message.image_url,
        image_object_key=message.image_object_key,
        created_at=message.created_at,
        edited_at=message.edited_at,
        deleted_at=message.deleted_at,
    )


@router.get('', response_model=list[DirectMessageChannelRead])
def list_dms(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> list[DirectMessageChannelRead]:
    channel_ids = db.scalars(
        select(ChannelMember.channel_id)
        .join(Channel, Channel.id == ChannelMember.channel_id)
        .where(
            ChannelMember.user_id == current_user.id,
            Channel.kind == 'dm',
            Channel.server_id.is_(None),
        )
    ).all()

    channels = [db.get(Channel, channel_id) for channel_id in channel_ids]
    valid_channels = [channel for channel in channels if channel is not None]

    return [_dm_channel_read(db, channel, current_user.id) for channel in valid_channels]


@router.post('/open', response_model=DirectMessageChannelRead, status_code=status.HTTP_201_CREATED)
def open_dm(
    payload: DirectMessageCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> DirectMessageChannelRead:
    peer = db.get(User, payload.peer_user_id)
    if peer is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Peer user not found.')

    if peer.id == current_user.id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Cannot DM yourself.')

    if peer.is_platform_admin and not current_user.is_platform_admin:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Peer user not found.')

    if not current_user.is_platform_admin:
        _ensure_friends(db, current_user.id, peer.id)

    existing = _find_dm_channel(db, current_user.id, peer.id)
    if existing is not None:
        return _dm_channel_read(db, existing, current_user.id)

    channel = Channel(name='direct-message', kind='dm', server_id=None, position=0)
    db.add(channel)
    db.flush()

    db.add(ChannelMember(channel_id=channel.id, user_id=current_user.id))
    db.add(ChannelMember(channel_id=channel.id, user_id=peer.id))

    db.commit()
    db.refresh(channel)

    return _dm_channel_read(db, channel, current_user.id)


@router.get('/{channel_id}/messages', response_model=list[DirectMessageMessageRead])
def list_dm_messages(
    channel_id: UUID,
    limit: int = Query(default=50, ge=1, le=200),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[DirectMessageMessageRead]:
    _require_dm_membership(db, channel_id, current_user.id)

    messages = db.scalars(
        select(Message)
        .where(Message.channel_id == channel_id)
        .order_by(Message.created_at.asc())
        .limit(limit)
    ).all()

    return [_dm_message_read(message) for message in messages]


@router.post('/{channel_id}/messages', response_model=DirectMessageMessageRead, status_code=status.HTTP_201_CREATED)
def create_dm_message(
    channel_id: UUID,
    payload: DirectMessageMessageCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> DirectMessageMessageRead:
    _require_dm_membership(db, channel_id, current_user.id)

    if payload.content is None and payload.image_url is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Message must include content or image_url.',
        )
    if payload.image_object_key is not None and payload.image_url is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='image_object_key requires image_url.',
        )

    image_expires_at = None
    if payload.image_url is not None:
        image_expires_at = datetime.now(timezone.utc) + timedelta(days=settings.upload_retention_days)

    message = Message(
        channel_id=channel_id,
        author_user_id=current_user.id,
        content=payload.content,
        image_url=payload.image_url,
        image_object_key=payload.image_object_key,
        image_expires_at=image_expires_at,
    )

    db.add(message)
    db.commit()
    db.refresh(message)

    message_read = _dm_message_read(message)
    realtime_hub.publish_dm_event(
        str(channel_id),
        event_type='dm.message.created',
        payload={'message': message_read.model_dump(mode='json')},
    )

    return message_read


@router.patch('/{channel_id}/messages/{message_id}', response_model=DirectMessageMessageRead)
def edit_dm_message(
    channel_id: UUID,
    message_id: UUID,
    payload: DirectMessageMessageEdit,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> DirectMessageMessageRead:
    _require_dm_membership(db, channel_id, current_user.id)

    message = db.scalar(
        select(Message).where(Message.id == message_id, Message.channel_id == channel_id)
    )
    if message is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Message not found.')

    if message.author_user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Can only edit your own message.')

    if message.deleted_at is not None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Cannot edit deleted message.')

    message.content = payload.content
    message.edited_at = datetime.now(timezone.utc)

    db.commit()
    db.refresh(message)

    message_read = _dm_message_read(message)
    realtime_hub.publish_dm_event(
        str(channel_id),
        event_type='dm.message.edited',
        payload={'message': message_read.model_dump(mode='json')},
    )

    return message_read


@router.delete('/{channel_id}/messages/{message_id}', status_code=status.HTTP_204_NO_CONTENT)
def delete_dm_message(
    channel_id: UUID,
    message_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    _require_dm_membership(db, channel_id, current_user.id)

    message = db.scalar(
        select(Message).where(Message.id == message_id, Message.channel_id == channel_id)
    )
    if message is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Message not found.')

    if message.author_user_id != current_user.id:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Can only delete your own message.')

    if message.deleted_at is None:
        message.deleted_at = datetime.now(timezone.utc)
        message.content = None
        message.image_url = None
        message.image_object_key = None
        db.commit()
        db.refresh(message)

        realtime_hub.publish_dm_event(
            str(channel_id),
            event_type='dm.message.deleted',
            payload={'message': _dm_message_read(message).model_dump(mode='json')},
        )

    return None
