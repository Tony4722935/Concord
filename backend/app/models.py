import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    UniqueConstraint,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy.types import Uuid

from app.database import Base


class User(Base):
    __tablename__ = 'users'
    __table_args__ = (
        UniqueConstraint('username_key', 'tag', name='uq_users_username_key_tag'),
        CheckConstraint('tag >= 0 AND tag <= 9999', name='ck_users_tag_range'),
    )

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    username: Mapped[str] = mapped_column(String(32), nullable=False)
    username_key: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    tag: Mapped[int] = mapped_column(Integer, nullable=False)
    display_name: Mapped[str | None] = mapped_column(String(64), nullable=True)
    avatar_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    avatar_object_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    password_hash: Mapped[str | None] = mapped_column(String(255), nullable=True)
    theme_preference: Mapped[str] = mapped_column(String(16), nullable=False, default='dark')
    language: Mapped[str] = mapped_column(String(16), nullable=False, default='en-US')
    time_format: Mapped[str] = mapped_column(String(8), nullable=False, default='24h')
    compact_mode: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    show_message_timestamps: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    is_platform_admin: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    owned_servers: Mapped[list['Server']] = relationship(back_populates='owner')
    refresh_tokens: Mapped[list['RefreshToken']] = relationship(
        back_populates='user',
        cascade='all, delete-orphan',
    )

    @property
    def handle(self) -> str:
        return f'{self.username}#{self.tag:04d}'


class Server(Base):
    __tablename__ = 'servers'

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    icon_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    icon_object_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    owner_user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('users.id', ondelete='RESTRICT'),
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    owner: Mapped['User'] = relationship(back_populates='owned_servers')
    members: Mapped[list['ServerMember']] = relationship(back_populates='server', cascade='all, delete-orphan')
    channels: Mapped[list['Channel']] = relationship(back_populates='server', cascade='all, delete-orphan')
    bans: Mapped[list['ServerBan']] = relationship(back_populates='server', cascade='all, delete-orphan')
    audit_logs: Mapped[list['ServerAuditLog']] = relationship(
        back_populates='server',
        cascade='all, delete-orphan',
    )
    invites: Mapped[list['ServerInvite']] = relationship(
        back_populates='server',
        cascade='all, delete-orphan',
    )


class ServerMember(Base):
    __tablename__ = 'server_members'
    __table_args__ = (UniqueConstraint('server_id', 'user_id', name='uq_server_members_server_user'),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    server_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('servers.id', ondelete='CASCADE'),
        nullable=False,
        index=True,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('users.id', ondelete='CASCADE'),
        nullable=False,
        index=True,
    )
    role: Mapped[str] = mapped_column(String(16), default='member', nullable=False)
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    server: Mapped['Server'] = relationship(back_populates='members')


class Channel(Base):
    __tablename__ = 'channels'
    __table_args__ = (UniqueConstraint('server_id', 'name', name='uq_channels_server_name'),)

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    server_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('servers.id', ondelete='CASCADE'),
        nullable=True,
        index=True,
    )
    name: Mapped[str] = mapped_column(String(64), nullable=False)
    kind: Mapped[str] = mapped_column(String(16), default='text', nullable=False)
    position: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    server: Mapped['Server'] = relationship(back_populates='channels')
    messages: Mapped[list['Message']] = relationship(back_populates='channel', cascade='all, delete-orphan')
    members: Mapped[list['ChannelMember']] = relationship(
        back_populates='channel',
        cascade='all, delete-orphan',
    )


class Message(Base):
    __tablename__ = 'messages'

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    channel_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('channels.id', ondelete='CASCADE'),
        nullable=False,
        index=True,
    )
    author_user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('users.id', ondelete='CASCADE'),
        nullable=False,
        index=True,
    )
    content: Mapped[str | None] = mapped_column(Text, nullable=True)
    image_url: Mapped[str | None] = mapped_column(Text, nullable=True)
    image_object_key: Mapped[str | None] = mapped_column(Text, nullable=True)
    image_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    edited_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    channel: Mapped['Channel'] = relationship(back_populates='messages')


class RefreshToken(Base):
    __tablename__ = 'refresh_tokens'

    id: Mapped[uuid.UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('users.id', ondelete='CASCADE'),
        nullable=False,
        index=True,
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    user: Mapped['User'] = relationship(back_populates='refresh_tokens')


class Friendship(Base):
    __tablename__ = 'friendships'
    __table_args__ = (UniqueConstraint('user_low_id', 'user_high_id', name='uq_friendships_pair'),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_low_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('users.id', ondelete='CASCADE'),
        nullable=False,
        index=True,
    )
    user_high_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('users.id', ondelete='CASCADE'),
        nullable=False,
        index=True,
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class ChannelMember(Base):
    __tablename__ = 'channel_members'
    __table_args__ = (UniqueConstraint('channel_id', 'user_id', name='uq_channel_members_channel_user'),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    channel_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('channels.id', ondelete='CASCADE'),
        nullable=False,
        index=True,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('users.id', ondelete='CASCADE'),
        nullable=False,
        index=True,
    )
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    channel: Mapped['Channel'] = relationship(back_populates='members')


class VoiceState(Base):
    __tablename__ = 'voice_states'
    __table_args__ = (
        UniqueConstraint('server_id', 'user_id', name='uq_voice_states_server_user'),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    server_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('servers.id', ondelete='CASCADE'),
        nullable=False,
        index=True,
    )
    channel_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('channels.id', ondelete='CASCADE'),
        nullable=False,
        index=True,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('users.id', ondelete='CASCADE'),
        nullable=False,
        index=True,
    )
    muted: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    deafened: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)


class ServerInvite(Base):
    __tablename__ = 'server_invites'
    __table_args__ = (UniqueConstraint('code', name='uq_server_invites_code'),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    server_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('servers.id', ondelete='CASCADE'),
        nullable=False,
        index=True,
    )
    code: Mapped[str] = mapped_column(String(32), nullable=False)
    created_by_user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('users.id', ondelete='CASCADE'),
        nullable=False,
        index=True,
    )
    max_uses: Mapped[int | None] = mapped_column(Integer, nullable=True)
    use_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    server: Mapped['Server'] = relationship(back_populates='invites')


class ServerBan(Base):
    __tablename__ = 'server_bans'
    __table_args__ = (UniqueConstraint('server_id', 'user_id', name='uq_server_bans_server_user'),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    server_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('servers.id', ondelete='CASCADE'),
        nullable=False,
        index=True,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('users.id', ondelete='CASCADE'),
        nullable=False,
        index=True,
    )
    banned_by_user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('users.id', ondelete='CASCADE'),
        nullable=False,
        index=True,
    )
    reason: Mapped[str | None] = mapped_column(String(512), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    server: Mapped['Server'] = relationship(back_populates='bans')


class ServerAuditLog(Base):
    __tablename__ = 'server_audit_logs'

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    server_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('servers.id', ondelete='CASCADE'),
        nullable=False,
        index=True,
    )
    actor_user_id: Mapped[uuid.UUID] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('users.id', ondelete='CASCADE'),
        nullable=False,
        index=True,
    )
    action: Mapped[str] = mapped_column(String(64), nullable=False)
    target_user_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('users.id', ondelete='SET NULL'),
        nullable=True,
        index=True,
    )
    target_channel_id: Mapped[uuid.UUID | None] = mapped_column(
        Uuid(as_uuid=True),
        ForeignKey('channels.id', ondelete='SET NULL'),
        nullable=True,
        index=True,
    )
    details_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), nullable=False)

    server: Mapped['Server'] = relationship(back_populates='audit_logs')
