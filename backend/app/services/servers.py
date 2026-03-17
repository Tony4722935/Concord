from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.models import Server, ServerMember, User

SERVER_MANAGE_ROLES = {'owner', 'admin'}


def require_server(db: Session, server_id: UUID) -> Server:
    server = db.get(Server, server_id)
    if server is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail='Server not found.')
    return server


def get_server_member(db: Session, server_id: UUID, user_id: UUID) -> ServerMember | None:
    return db.scalar(
        select(ServerMember).where(ServerMember.server_id == server_id, ServerMember.user_id == user_id)
    )


def require_server_member(db: Session, server_id: UUID, user: User) -> ServerMember:
    if user.is_platform_admin:
        return ServerMember(server_id=server_id, user_id=user.id, role='owner')

    member = get_server_member(db, server_id, user.id)
    if member is None:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Not a member of this server.')
    return member


def require_server_manage_permission(db: Session, server_id: UUID, user: User) -> ServerMember:
    if user.is_platform_admin:
        return ServerMember(server_id=server_id, user_id=user.id, role='owner')

    member = require_server_member(db, server_id, user)
    if member.role not in SERVER_MANAGE_ROLES:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Insufficient server permissions.')
    return member


def require_server_owner(db: Session, server_id: UUID, user: User) -> ServerMember:
    if user.is_platform_admin:
        return ServerMember(server_id=server_id, user_id=user.id, role='owner')

    member = require_server_member(db, server_id, user)
    if member.role != 'owner':
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail='Only server owner can do this action.')
    return member
