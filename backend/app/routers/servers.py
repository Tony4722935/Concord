import secrets
import json
from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session

from app.config import settings
from app.database import get_db
from app.models import (
    Channel,
    Message,
    Server,
    ServerAuditLog,
    ServerBan,
    ServerInvite,
    ServerMember,
    User,
    VoiceState,
)
from app.realtime import realtime_hub
from app.schemas import (
    ChannelCreate,
    ChannelRead,
    ChannelUpdate,
    ImageAssetUpdate,
    ServerAuditLogRead,
    ServerChannelMessageCreate,
    ServerChannelMessageEdit,
    ServerChannelMessageRead,
    ServerCreate,
    ServerInviteCreate,
    ServerInviteRead,
    ServerJoinByInvite,
    ServerMemberRead,
    ServerMemberRoleUpdate,
    ServerOnlineMembersRead,
    ServerOwnershipTransfer,
    ServerBanCreate,
    ServerBanRead,
    VoiceStateRead,
    VoiceStateUpdate,
    ServerRead,
    ServerUpdate,
)
from app.security import get_current_user
from app.services.servers import (
    get_server_member,
    require_server,
    require_server_manage_permission,
    require_server_member,
    require_server_owner,
)
from app.services.media import (
    collect_message_object_keys,
    delete_storage_objects,
    resolve_storage_object_key,
)

router = APIRouter(prefix='/servers', tags=['servers'])


def _member_read(user: User, member: ServerMember) -> ServerMemberRead:
    return ServerMemberRead(
        user_id=user.id,
        username=user.username,
        tag=user.tag,
        handle=user.handle,
        display_name=user.display_name,
        avatar_url=user.avatar_url,
        role=member.role,
        joined_at=member.joined_at,
    )


def _voice_state_read(user: User, state: VoiceState) -> VoiceStateRead:
    return VoiceStateRead(
        user_id=user.id,
        channel_id=state.channel_id,
        muted=state.muted,
        deafened=state.deafened,
        joined_at=state.joined_at,
        handle=user.handle,
        display_name=user.display_name,
        avatar_url=user.avatar_url,
    )


def _invite_read(invite: ServerInvite) -> ServerInviteRead:
    return ServerInviteRead(
        code=invite.code,
        server_id=invite.server_id,
        created_by_user_id=invite.created_by_user_id,
        max_uses=invite.max_uses,
        use_count=invite.use_count,
        expires_at=invite.expires_at,
        revoked_at=invite.revoked_at,
        created_at=invite.created_at,
    )


def _ban_read(user: User, ban: ServerBan) -> ServerBanRead:
    return ServerBanRead(
        user_id=user.id,
        user_handle=user.handle,
        user_display_name=user.display_name,
        banned_by_user_id=ban.banned_by_user_id,
        reason=ban.reason,
        created_at=ban.created_at,
    )


def _audit_log_read(
    audit: ServerAuditLog,
    actor_user: User | None,
    target_user: User | None,
) -> ServerAuditLogRead:
    details = None
    if audit.details_json:
        try:
            details = json.loads(audit.details_json)
        except ValueError:
            details = {'raw': audit.details_json}

    return ServerAuditLogRead(
        log_id=audit.id,
        action=audit.action,
        actor_user_id=audit.actor_user_id,
        actor_handle=actor_user.handle if actor_user else None,
        target_user_id=audit.target_user_id,
        target_handle=target_user.handle if target_user else None,
        target_channel_id=audit.target_channel_id,
        details=details,
        created_at=audit.created_at,
    )


def _generate_invite_code() -> str:
    return secrets.token_urlsafe(8).replace('-', '').replace('_', '')[:10]


def _require_server_channel(db: Session, server_id: UUID, channel_id: UUID) -> Channel:
    channel = db.scalar(select(Channel).where(Channel.id == channel_id, Channel.server_id == server_id))
    if channel is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Channel not found in server.')

    if channel.kind == 'dm':
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Invalid channel kind for server.')

    return channel


def _require_server_voice_channel(db: Session, server_id: UUID, channel_id: UUID) -> Channel:
    channel = db.scalar(select(Channel).where(Channel.id == channel_id, Channel.server_id == server_id))
    if channel is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Channel not found in server.')

    if channel.kind != 'voice':
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Voice channel required.')

    return channel


def _server_message_read(message: Message) -> ServerChannelMessageRead:
    return ServerChannelMessageRead(
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


def _reorder_server_channels(db: Session, server_id: UUID, moving_channel_id: UUID, target_position: int) -> None:
    channels = db.scalars(
        select(Channel)
        .where(Channel.server_id == server_id)
        .order_by(Channel.position.asc(), Channel.created_at.asc())
    ).all()
    if not channels:
        return

    moving = next((channel for channel in channels if channel.id == moving_channel_id), None)
    if moving is None:
        return

    channels = [channel for channel in channels if channel.id != moving_channel_id]
    clamped = max(0, min(target_position, len(channels)))
    channels.insert(clamped, moving)

    for index, channel in enumerate(channels):
        channel.position = index


def _role_rank(role: str) -> int:
    if role == 'owner':
        return 2
    if role == 'admin':
        return 1
    return 0


def _write_audit_log(
    db: Session,
    *,
    server_id: UUID,
    actor_user_id: UUID,
    action: str,
    target_user_id: UUID | None = None,
    target_channel_id: UUID | None = None,
    details: dict | None = None,
) -> None:
    db.add(
        ServerAuditLog(
            server_id=server_id,
            actor_user_id=actor_user_id,
            action=action,
            target_user_id=target_user_id,
            target_channel_id=target_channel_id,
            details_json=json.dumps(details) if details else None,
        )
    )


@router.get('', response_model=list[ServerRead])
def list_my_servers(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)) -> list[Server]:
    if current_user.is_platform_admin:
        servers = db.scalars(
            select(Server)
            .order_by(Server.created_at.desc())
        ).all()
        return list(servers)

    servers = db.scalars(
        select(Server)
        .join(ServerMember, ServerMember.server_id == Server.id)
        .where(ServerMember.user_id == current_user.id)
        .order_by(Server.created_at.desc())
    ).all()
    return list(servers)


@router.post('', response_model=ServerRead, status_code=status.HTTP_201_CREATED)
def create_server(
    payload: ServerCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Server:
    server = Server(name=payload.name, owner_user_id=current_user.id)
    db.add(server)
    db.flush()

    db.add(
        ServerMember(
            server_id=server.id,
            user_id=current_user.id,
            role='owner',
        )
    )

    db.add(
        Channel(
            server_id=server.id,
            name='general',
            kind='text',
            position=0,
        )
    )

    _write_audit_log(
        db,
        server_id=server.id,
        actor_user_id=current_user.id,
        action='server.create',
        details={'server_name': server.name},
    )

    db.commit()
    db.refresh(server)
    return server


@router.get('/{server_id}', response_model=ServerRead)
def get_server(
    server_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Server:
    server = require_server(db, server_id)
    require_server_member(db, server_id, current_user)
    return server


@router.patch('/{server_id}', response_model=ServerRead)
def update_server(
    server_id: UUID,
    payload: ServerUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Server:
    server = require_server(db, server_id)
    require_server_manage_permission(db, server_id, current_user)

    old_name = server.name
    server.name = payload.name

    _write_audit_log(
        db,
        server_id=server.id,
        actor_user_id=current_user.id,
        action='server.update',
        details={'old_name': old_name, 'new_name': server.name},
    )

    db.commit()
    db.refresh(server)
    return server


@router.delete('/{server_id}', status_code=status.HTTP_204_NO_CONTENT)
def delete_server(
    server_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    server = require_server(db, server_id)
    require_server_owner(db, server_id, current_user)

    message_rows = db.execute(
        select(Message.image_object_key, Message.image_url)
        .join(Channel, Channel.id == Message.channel_id)
        .where(
            Channel.server_id == server_id,
            or_(Message.image_object_key.is_not(None), Message.image_url.is_not(None)),
        )
    ).all()
    object_keys = collect_message_object_keys(message_rows)
    icon_key = resolve_storage_object_key(server.icon_object_key, server.icon_url)
    if icon_key:
        object_keys.add(icon_key)
    if object_keys:
        try:
            delete_storage_objects(object_keys)
        except RuntimeError as error:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=f'Unable to delete server uploads: {error}',
            ) from error
        except Exception as error:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail='Failed to delete one or more server uploads.',
            ) from error

    db.delete(server)
    db.commit()
    return None


@router.put('/{server_id}/icon', response_model=ServerRead)
def update_server_icon(
    server_id: UUID,
    payload: ImageAssetUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Server:
    server = require_server(db, server_id)
    require_server_manage_permission(db, server_id, current_user)

    previous_key = resolve_storage_object_key(server.icon_object_key, server.icon_url)
    next_key = resolve_storage_object_key(payload.image_object_key, payload.image_url)

    server.icon_url = payload.image_url
    server.icon_object_key = payload.image_object_key

    _write_audit_log(
        db,
        server_id=server.id,
        actor_user_id=current_user.id,
        action='server.icon.update',
    )

    db.commit()
    db.refresh(server)

    if previous_key and previous_key != next_key:
        try:
            delete_storage_objects([previous_key])
        except Exception:
            # Best effort cleanup when replacing server icon.
            pass

    return server


@router.delete('/{server_id}/icon', response_model=ServerRead)
def clear_server_icon(
    server_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Server:
    server = require_server(db, server_id)
    require_server_manage_permission(db, server_id, current_user)

    previous_key = resolve_storage_object_key(server.icon_object_key, server.icon_url)
    server.icon_url = None
    server.icon_object_key = None

    _write_audit_log(
        db,
        server_id=server.id,
        actor_user_id=current_user.id,
        action='server.icon.clear',
    )

    db.commit()
    db.refresh(server)

    if previous_key:
        try:
            delete_storage_objects([previous_key])
        except Exception:
            # Best effort cleanup when clearing server icon.
            pass

    return server


@router.get('/{server_id}/channels', response_model=list[ChannelRead])
def list_server_channels(
    server_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[Channel]:
    require_server(db, server_id)
    require_server_member(db, server_id, current_user)

    channels = db.scalars(
        select(Channel)
        .where(Channel.server_id == server_id)
        .order_by(Channel.position.asc(), Channel.created_at.asc())
    ).all()
    return list(channels)


@router.get('/{server_id}/voice/me', response_model=VoiceStateRead | None)
def get_my_voice_state(
    server_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> VoiceStateRead | None:
    require_server(db, server_id)
    require_server_member(db, server_id, current_user)

    state = db.scalar(
        select(VoiceState).where(
            VoiceState.server_id == server_id,
            VoiceState.user_id == current_user.id,
        )
    )
    if state is None:
        return None

    return _voice_state_read(current_user, state)


@router.get('/{server_id}/channels/{channel_id}/voice/states', response_model=list[VoiceStateRead])
def list_voice_states(
    server_id: UUID,
    channel_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[VoiceStateRead]:
    require_server(db, server_id)
    require_server_member(db, server_id, current_user)
    _require_server_voice_channel(db, server_id, channel_id)

    states = db.scalars(
        select(VoiceState)
        .where(VoiceState.server_id == server_id, VoiceState.channel_id == channel_id)
        .order_by(VoiceState.joined_at.asc())
    ).all()

    users = {
        user.id: user
        for user in db.scalars(select(User).where(User.id.in_([state.user_id for state in states]))).all()
    }

    result: list[VoiceStateRead] = []
    for state in states:
        user = users.get(state.user_id)
        if user is None:
            continue
        result.append(_voice_state_read(user, state))
    return result


@router.put('/{server_id}/channels/{channel_id}/voice/state', response_model=VoiceStateRead)
def join_or_update_voice_state(
    server_id: UUID,
    channel_id: UUID,
    payload: VoiceStateUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> VoiceStateRead:
    require_server(db, server_id)
    require_server_member(db, server_id, current_user)
    channel = _require_server_voice_channel(db, server_id, channel_id)

    existing = db.scalar(
        select(VoiceState).where(
            VoiceState.server_id == server_id,
            VoiceState.user_id == current_user.id,
        )
    )
    previous_channel_id: UUID | None = None
    if existing is None:
        existing = VoiceState(
            server_id=server_id,
            channel_id=channel.id,
            user_id=current_user.id,
            muted=payload.muted,
            deafened=payload.deafened,
        )
        db.add(existing)
        action = 'voice.join'
    else:
        previous_channel_id = existing.channel_id
        existing.channel_id = channel.id
        existing.muted = payload.muted
        existing.deafened = payload.deafened
        action = 'voice.move' if previous_channel_id != channel.id else 'voice.update'

    _write_audit_log(
        db,
        server_id=server_id,
        actor_user_id=current_user.id,
        action=action,
        target_channel_id=channel.id,
        details={
            'muted': existing.muted,
            'deafened': existing.deafened,
            'previous_channel_id': str(previous_channel_id) if previous_channel_id else None,
        },
    )

    db.commit()
    db.refresh(existing)
    read = _voice_state_read(current_user, existing)

    realtime_hub.publish_server_channel_event(
        str(channel.id),
        event_type='voice.state.updated',
        payload={'voice_state': read.model_dump(mode='json')},
    )
    if previous_channel_id is not None and previous_channel_id != channel.id:
        realtime_hub.publish_server_channel_event(
            str(previous_channel_id),
            event_type='voice.state.updated',
            payload={'voice_state': read.model_dump(mode='json')},
        )

    return read


@router.delete('/{server_id}/channels/{channel_id}/voice/state', status_code=status.HTTP_204_NO_CONTENT)
def leave_voice_state(
    server_id: UUID,
    channel_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    require_server(db, server_id)
    require_server_member(db, server_id, current_user)
    _require_server_voice_channel(db, server_id, channel_id)

    state = db.scalar(
        select(VoiceState).where(
            VoiceState.server_id == server_id,
            VoiceState.user_id == current_user.id,
            VoiceState.channel_id == channel_id,
        )
    )
    if state is None:
        return None

    _write_audit_log(
        db,
        server_id=server_id,
        actor_user_id=current_user.id,
        action='voice.leave',
        target_channel_id=channel_id,
        details={'muted': state.muted, 'deafened': state.deafened},
    )

    db.delete(state)
    db.commit()
    realtime_hub.publish_server_channel_event(
        str(channel_id),
        event_type='voice.state.left',
        payload={'user_id': str(current_user.id), 'channel_id': str(channel_id)},
    )
    return None


@router.get('/{server_id}/audit-logs', response_model=list[ServerAuditLogRead])
def list_server_audit_logs(
    server_id: UUID,
    response: Response,
    limit: int = Query(default=100, ge=1, le=200),
    cursor_log_id: int | None = Query(default=None, ge=1),
    action: str | None = Query(default=None, max_length=64),
    actor_user_id: UUID | None = Query(default=None),
    target_user_id: UUID | None = Query(default=None),
    created_before: datetime | None = Query(default=None),
    created_after: datetime | None = Query(default=None),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[ServerAuditLogRead]:
    require_server(db, server_id)
    require_server_manage_permission(db, server_id, current_user)

    stmt = select(ServerAuditLog).where(ServerAuditLog.server_id == server_id)
    if cursor_log_id is not None:
        stmt = stmt.where(ServerAuditLog.id < cursor_log_id)
    if action:
        stmt = stmt.where(ServerAuditLog.action == action.strip())
    if actor_user_id is not None:
        stmt = stmt.where(ServerAuditLog.actor_user_id == actor_user_id)
    if target_user_id is not None:
        stmt = stmt.where(ServerAuditLog.target_user_id == target_user_id)
    if created_before is not None:
        stmt = stmt.where(ServerAuditLog.created_at < created_before)
    if created_after is not None:
        stmt = stmt.where(ServerAuditLog.created_at > created_after)

    audits = db.scalars(stmt.order_by(ServerAuditLog.id.desc()).limit(limit)).all()

    result: list[ServerAuditLogRead] = []
    for audit in audits:
        actor_user = db.get(User, audit.actor_user_id)
        target_user = db.get(User, audit.target_user_id) if audit.target_user_id else None
        result.append(_audit_log_read(audit, actor_user, target_user))

    if result and len(result) == limit:
        response.headers['X-Next-Cursor'] = str(result[-1].log_id)
    else:
        response.headers['X-Next-Cursor'] = ''

    return result


@router.get('/{server_id}/channels/{channel_id}/messages', response_model=list[ServerChannelMessageRead])
def list_server_channel_messages(
    server_id: UUID,
    channel_id: UUID,
    limit: int = Query(default=50, ge=1, le=200),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[ServerChannelMessageRead]:
    require_server(db, server_id)
    require_server_member(db, server_id, current_user)
    _require_server_channel(db, server_id, channel_id)

    messages = db.scalars(
        select(Message)
        .where(Message.channel_id == channel_id)
        .order_by(Message.created_at.asc())
        .limit(limit)
    ).all()

    return [_server_message_read(message) for message in messages]


@router.post(
    '/{server_id}/channels/{channel_id}/messages',
    response_model=ServerChannelMessageRead,
    status_code=status.HTTP_201_CREATED,
)
def create_server_channel_message(
    server_id: UUID,
    channel_id: UUID,
    payload: ServerChannelMessageCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ServerChannelMessageRead:
    require_server(db, server_id)
    require_server_member(db, server_id, current_user)
    _require_server_channel(db, server_id, channel_id)

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

    message_read = _server_message_read(message)
    realtime_hub.publish_server_channel_event(
        str(channel_id),
        event_type='server.message.created',
        payload={'message': message_read.model_dump(mode='json')},
    )

    return message_read


@router.patch(
    '/{server_id}/channels/{channel_id}/messages/{message_id}',
    response_model=ServerChannelMessageRead,
)
def edit_server_channel_message(
    server_id: UUID,
    channel_id: UUID,
    message_id: UUID,
    payload: ServerChannelMessageEdit,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ServerChannelMessageRead:
    require_server(db, server_id)
    require_server_member(db, server_id, current_user)
    _require_server_channel(db, server_id, channel_id)

    message = db.scalar(select(Message).where(Message.id == message_id, Message.channel_id == channel_id))
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

    message_read = _server_message_read(message)
    realtime_hub.publish_server_channel_event(
        str(channel_id),
        event_type='server.message.edited',
        payload={'message': message_read.model_dump(mode='json')},
    )

    return message_read


@router.delete(
    '/{server_id}/channels/{channel_id}/messages/{message_id}',
    status_code=status.HTTP_204_NO_CONTENT,
)
def delete_server_channel_message(
    server_id: UUID,
    channel_id: UUID,
    message_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    require_server(db, server_id)
    require_server_member(db, server_id, current_user)
    _require_server_channel(db, server_id, channel_id)

    message = db.scalar(select(Message).where(Message.id == message_id, Message.channel_id == channel_id))
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

        realtime_hub.publish_server_channel_event(
            str(channel_id),
            event_type='server.message.deleted',
            payload={'message': _server_message_read(message).model_dump(mode='json')},
        )

    return None


@router.post('/{server_id}/channels', response_model=ChannelRead, status_code=status.HTTP_201_CREATED)
def create_server_channel(
    server_id: UUID,
    payload: ChannelCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Channel:
    require_server(db, server_id)
    require_server_manage_permission(db, server_id, current_user)

    existing = db.scalar(
        select(Channel).where(Channel.server_id == server_id, Channel.name == payload.name)
    )
    if existing is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail='Channel name already exists in this server.',
        )

    max_position = db.scalar(select(func.max(Channel.position)).where(Channel.server_id == server_id))
    next_position = (max_position or 0) + 1 if max_position is not None else 0

    channel = Channel(
        server_id=server_id,
        name=payload.name,
        kind=payload.kind,
        position=next_position,
    )

    db.add(channel)
    db.flush()

    _write_audit_log(
        db,
        server_id=server_id,
        actor_user_id=current_user.id,
        action='channel.create',
        target_channel_id=channel.id,
        details={'name': channel.name, 'kind': channel.kind, 'position': channel.position},
    )

    db.commit()
    db.refresh(channel)
    return channel


@router.patch('/{server_id}/channels/{channel_id}', response_model=ChannelRead)
def update_server_channel(
    server_id: UUID,
    channel_id: UUID,
    payload: ChannelUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Channel:
    require_server(db, server_id)
    require_server_manage_permission(db, server_id, current_user)
    channel = _require_server_channel(db, server_id, channel_id)
    old_name = channel.name
    old_position = channel.position

    if payload.name is not None and payload.name != channel.name:
        existing = db.scalar(
            select(Channel).where(
                Channel.server_id == server_id,
                Channel.name == payload.name,
                Channel.id != channel.id,
            )
        )
        if existing is not None:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail='Channel name already exists in this server.',
            )
        channel.name = payload.name

    if payload.position is not None:
        _reorder_server_channels(db, server_id, channel.id, payload.position)

    _write_audit_log(
        db,
        server_id=server_id,
        actor_user_id=current_user.id,
        action='channel.update',
        target_channel_id=channel.id,
        details={
            'old_name': old_name,
            'new_name': channel.name,
            'old_position': old_position,
            'new_position': channel.position,
        },
    )

    db.commit()
    db.refresh(channel)
    return channel


@router.delete('/{server_id}/channels/{channel_id}', status_code=status.HTTP_204_NO_CONTENT)
def delete_server_channel(
    server_id: UUID,
    channel_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    require_server(db, server_id)
    require_server_manage_permission(db, server_id, current_user)
    channel = _require_server_channel(db, server_id, channel_id)
    deleted_channel_id = channel.id
    deleted_name = channel.name
    deleted_position = channel.position

    total_channel_count = db.scalar(select(func.count(Channel.id)).where(Channel.server_id == server_id)) or 0
    if total_channel_count <= 1:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Server must keep at least one channel.',
        )

    message_rows = db.execute(
        select(Message.image_object_key, Message.image_url).where(
            Message.channel_id == channel_id,
            or_(Message.image_object_key.is_not(None), Message.image_url.is_not(None)),
        )
    ).all()
    object_keys = collect_message_object_keys(message_rows)
    if object_keys:
        try:
            delete_storage_objects(object_keys)
        except RuntimeError as error:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=f'Unable to delete channel uploads: {error}',
            ) from error
        except Exception as error:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail='Failed to delete one or more channel uploads.',
            ) from error

    db.delete(channel)
    db.flush()

    remaining_channels = db.scalars(
        select(Channel)
        .where(Channel.server_id == server_id)
        .order_by(Channel.position.asc(), Channel.created_at.asc())
    ).all()
    for index, remaining in enumerate(remaining_channels):
        remaining.position = index

    _write_audit_log(
        db,
        server_id=server_id,
        actor_user_id=current_user.id,
        action='channel.delete',
        target_channel_id=deleted_channel_id,
        details={'name': deleted_name, 'position': deleted_position},
    )

    db.commit()
    return None


@router.get('/{server_id}/members', response_model=list[ServerMemberRead])
def list_server_members(
    server_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[ServerMemberRead]:
    require_server(db, server_id)
    require_server_member(db, server_id, current_user)

    member_rows = db.scalars(
        select(ServerMember)
        .where(ServerMember.server_id == server_id)
        .order_by(ServerMember.joined_at.asc())
    ).all()

    result: list[ServerMemberRead] = []
    for member in member_rows:
        user = db.get(User, member.user_id)
        if user is None:
            continue
        result.append(_member_read(user, member))

    return result


@router.get('/{server_id}/members/online', response_model=ServerOnlineMembersRead)
def list_server_online_members(
    server_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ServerOnlineMembersRead:
    require_server(db, server_id)
    require_server_member(db, server_id, current_user)

    member_ids = db.scalars(
        select(ServerMember.user_id).where(ServerMember.server_id == server_id)
    ).all()
    online_ids = set(realtime_hub.online_user_ids())
    online_member_ids = [member_id for member_id in member_ids if str(member_id) in online_ids]

    return ServerOnlineMembersRead(
        total_count=len(member_ids),
        online_count=len(online_member_ids),
        online_user_ids=online_member_ids,
    )


@router.patch('/{server_id}/members/{member_user_id}/role', response_model=ServerMemberRead)
def update_server_member_role(
    server_id: UUID,
    member_user_id: UUID,
    payload: ServerMemberRoleUpdate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ServerMemberRead:
    require_server(db, server_id)
    require_server_owner(db, server_id, current_user)

    target_member = get_server_member(db, server_id, member_user_id)
    if target_member is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Member not found.')

    if target_member.role == 'owner':
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Owner role cannot be changed with this endpoint.',
        )

    old_role = target_member.role
    target_member.role = payload.role

    _write_audit_log(
        db,
        server_id=server_id,
        actor_user_id=current_user.id,
        action='member.role.update',
        target_user_id=target_member.user_id,
        details={'old_role': old_role, 'new_role': target_member.role},
    )

    db.commit()
    db.refresh(target_member)

    target_user = db.get(User, target_member.user_id)
    if target_user is None:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail='Member user missing.')

    return _member_read(target_user, target_member)


@router.post('/{server_id}/members/{member_user_id}/kick', status_code=status.HTTP_204_NO_CONTENT)
def kick_server_member(
    server_id: UUID,
    member_user_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    require_server(db, server_id)
    acting_member = require_server_manage_permission(db, server_id, current_user)

    if member_user_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Use leave server endpoint for yourself.',
        )

    target_member = get_server_member(db, server_id, member_user_id)
    if target_member is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Member not found.')

    if _role_rank(acting_member.role) <= _role_rank(target_member.role):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Cannot moderate member with equal or higher role.',
        )

    kicked_user_id = target_member.user_id
    kicked_role = target_member.role
    db.delete(target_member)
    active_voice_state = db.scalar(
        select(VoiceState).where(
            VoiceState.server_id == server_id,
            VoiceState.user_id == kicked_user_id,
        )
    )
    if active_voice_state is not None:
        db.delete(active_voice_state)

    _write_audit_log(
        db,
        server_id=server_id,
        actor_user_id=current_user.id,
        action='member.kick',
        target_user_id=kicked_user_id,
        details={'role': kicked_role},
    )

    db.commit()
    return None


@router.get('/{server_id}/bans', response_model=list[ServerBanRead])
def list_server_bans(
    server_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[ServerBanRead]:
    require_server(db, server_id)
    require_server_manage_permission(db, server_id, current_user)

    bans = db.scalars(
        select(ServerBan)
        .where(ServerBan.server_id == server_id)
        .order_by(ServerBan.created_at.desc())
    ).all()

    result: list[ServerBanRead] = []
    for ban in bans:
        user = db.get(User, ban.user_id)
        if user is None:
            continue
        result.append(_ban_read(user, ban))
    return result


@router.post('/{server_id}/bans/{target_user_id}', response_model=ServerBanRead, status_code=status.HTTP_201_CREATED)
def ban_server_user(
    server_id: UUID,
    target_user_id: UUID,
    payload: ServerBanCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ServerBanRead:
    require_server(db, server_id)
    acting_member = require_server_manage_permission(db, server_id, current_user)

    if target_user_id == current_user.id:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Cannot ban yourself.')

    target_user = db.get(User, target_user_id)
    if target_user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Target user not found.')

    existing_ban = db.scalar(
        select(ServerBan).where(ServerBan.server_id == server_id, ServerBan.user_id == target_user_id)
    )
    if existing_ban is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail='User is already banned.')

    target_member = get_server_member(db, server_id, target_user_id)
    if target_member is not None and _role_rank(acting_member.role) <= _role_rank(target_member.role):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail='Cannot moderate member with equal or higher role.',
        )

    if target_member is not None:
        db.delete(target_member)
        db.flush()
    active_voice_state = db.scalar(
        select(VoiceState).where(
            VoiceState.server_id == server_id,
            VoiceState.user_id == target_user_id,
        )
    )
    if active_voice_state is not None:
        db.delete(active_voice_state)
        db.flush()

    ban = ServerBan(
        server_id=server_id,
        user_id=target_user_id,
        banned_by_user_id=current_user.id,
        reason=payload.reason,
    )
    db.add(ban)
    db.flush()

    _write_audit_log(
        db,
        server_id=server_id,
        actor_user_id=current_user.id,
        action='member.ban',
        target_user_id=target_user_id,
        details={'reason': payload.reason},
    )

    db.commit()
    db.refresh(ban)

    return _ban_read(target_user, ban)


@router.delete('/{server_id}/bans/{target_user_id}', status_code=status.HTTP_204_NO_CONTENT)
def unban_server_user(
    server_id: UUID,
    target_user_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    require_server(db, server_id)
    require_server_manage_permission(db, server_id, current_user)

    ban = db.scalar(select(ServerBan).where(ServerBan.server_id == server_id, ServerBan.user_id == target_user_id))
    if ban is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Ban not found.')

    unbanned_user_id = ban.user_id
    db.delete(ban)

    _write_audit_log(
        db,
        server_id=server_id,
        actor_user_id=current_user.id,
        action='member.unban',
        target_user_id=unbanned_user_id,
    )

    db.commit()
    return None


@router.post('/{server_id}/transfer-ownership', response_model=ServerRead)
def transfer_server_ownership(
    server_id: UUID,
    payload: ServerOwnershipTransfer,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Server:
    server = require_server(db, server_id)
    current_member = require_server_owner(db, server_id, current_user)

    if payload.new_owner_user_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Cannot transfer ownership to yourself.',
        )

    target_member = get_server_member(db, server_id, payload.new_owner_user_id)
    if target_member is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail='Target member not found in this server.',
        )

    server.owner_user_id = payload.new_owner_user_id
    current_member.role = 'admin'
    target_member.role = 'owner'

    _write_audit_log(
        db,
        server_id=server_id,
        actor_user_id=current_user.id,
        action='server.ownership.transfer',
        target_user_id=payload.new_owner_user_id,
        details={'previous_owner_user_id': str(current_user.id)},
    )

    db.commit()
    db.refresh(server)
    return server


@router.post('/{server_id}/leave', status_code=status.HTTP_204_NO_CONTENT)
def leave_server(
    server_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    server = require_server(db, server_id)
    member = require_server_member(db, server_id, current_user)

    if member.role == 'owner' or server.owner_user_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail='Owner must transfer ownership before leaving the server.',
        )

    leaving_role = member.role
    db.delete(member)
    active_voice_state = db.scalar(
        select(VoiceState).where(
            VoiceState.server_id == server_id,
            VoiceState.user_id == current_user.id,
        )
    )
    if active_voice_state is not None:
        db.delete(active_voice_state)

    _write_audit_log(
        db,
        server_id=server_id,
        actor_user_id=current_user.id,
        action='member.leave',
        target_user_id=current_user.id,
        details={'role': leaving_role},
    )

    db.commit()
    return None


@router.post('/{server_id}/invites', response_model=ServerInviteRead, status_code=status.HTTP_201_CREATED)
def create_server_invite(
    server_id: UUID,
    payload: ServerInviteCreate,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> ServerInviteRead:
    require_server(db, server_id)
    require_server_manage_permission(db, server_id, current_user)

    now = datetime.now(timezone.utc)
    expires_at = None
    if payload.expires_in_hours is not None:
        expires_at = now + timedelta(hours=payload.expires_in_hours)

    code = _generate_invite_code()
    while db.scalar(select(ServerInvite).where(ServerInvite.code == code)) is not None:
        code = _generate_invite_code()

    invite = ServerInvite(
        server_id=server_id,
        code=code,
        created_by_user_id=current_user.id,
        max_uses=payload.max_uses,
        use_count=0,
        expires_at=expires_at,
    )

    db.add(invite)
    db.flush()

    _write_audit_log(
        db,
        server_id=server_id,
        actor_user_id=current_user.id,
        action='invite.create',
        details={
            'code': invite.code,
            'max_uses': invite.max_uses,
            'expires_at': invite.expires_at.isoformat() if invite.expires_at else None,
        },
    )

    db.commit()
    db.refresh(invite)

    return _invite_read(invite)


@router.get('/{server_id}/invites', response_model=list[ServerInviteRead])
def list_server_invites(
    server_id: UUID,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> list[ServerInviteRead]:
    require_server(db, server_id)
    require_server_manage_permission(db, server_id, current_user)
    now = datetime.now(timezone.utc)

    invites = db.scalars(
        select(ServerInvite)
        .where(ServerInvite.server_id == server_id)
        .where(ServerInvite.revoked_at.is_(None))
        .where((ServerInvite.expires_at.is_(None)) | (ServerInvite.expires_at > now))
        .order_by(ServerInvite.created_at.desc())
    ).all()

    return [_invite_read(invite) for invite in invites]


@router.delete('/{server_id}/invites/{code}', status_code=status.HTTP_204_NO_CONTENT)
def revoke_server_invite(
    server_id: UUID,
    code: str,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> None:
    require_server(db, server_id)
    require_server_manage_permission(db, server_id, current_user)

    invite = db.scalar(
        select(ServerInvite).where(ServerInvite.server_id == server_id, ServerInvite.code == code)
    )
    if invite is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Invite not found.')

    if invite.revoked_at is None:
        invite.revoked_at = datetime.now(timezone.utc)

        _write_audit_log(
            db,
            server_id=server_id,
            actor_user_id=current_user.id,
            action='invite.revoke',
            details={'code': invite.code},
        )

        db.commit()

    return None


@router.post('/join-by-invite', response_model=ServerRead)
def join_server_by_invite(
    payload: ServerJoinByInvite,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
) -> Server:
    invite = db.scalar(select(ServerInvite).where(ServerInvite.code == payload.code))
    if invite is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Invite not found.')

    now = datetime.now(timezone.utc)
    if invite.revoked_at is not None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Invite is revoked.')

    if invite.expires_at is not None and invite.expires_at <= now:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Invite has expired.')

    if invite.max_uses is not None and invite.use_count >= invite.max_uses:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail='Invite has reached max uses.')

    server = require_server(db, invite.server_id)
    existing_ban = db.scalar(
        select(ServerBan).where(ServerBan.server_id == server.id, ServerBan.user_id == current_user.id)
    )
    if existing_ban is not None:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='You are banned from this server.')

    existing_member = get_server_member(db, server.id, current_user.id)
    if existing_member is None:
        db.add(
            ServerMember(
                server_id=server.id,
                user_id=current_user.id,
                role='member',
            )
        )
        invite.use_count += 1

        _write_audit_log(
            db,
            server_id=server.id,
            actor_user_id=current_user.id,
            action='member.join',
            target_user_id=current_user.id,
            details={'invite_code': invite.code},
        )

        db.commit()

    return server
