from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


USERNAME_REGEX = r'^[A-Za-z0-9_]{2,32}$'
CHANNEL_REGEX = r'^[a-z0-9-]{1,64}$'


class UserCreate(BaseModel):
    username: str = Field(min_length=2, max_length=32, pattern=USERNAME_REGEX)
    display_name: str | None = Field(default=None, max_length=64)
    password: str | None = Field(default=None, min_length=8, max_length=128)

    @field_validator('username')
    @classmethod
    def normalize_username(cls, value: str) -> str:
        return value.strip()


class UserRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    username: str
    tag: int
    handle: str
    display_name: str | None
    avatar_url: str | None
    avatar_object_key: str | None
    theme_preference: str
    language: str
    time_format: str
    compact_mode: bool
    show_message_timestamps: bool
    is_platform_admin: bool


class AuthRegister(BaseModel):
    username: str = Field(min_length=2, max_length=32, pattern=USERNAME_REGEX)
    password: str = Field(min_length=8, max_length=128)
    display_name: str | None = Field(default=None, max_length=64)
    preferred_tag: int | None = Field(default=None, ge=0, le=9999)

    @field_validator('username')
    @classmethod
    def normalize_username(cls, value: str) -> str:
        return value.strip()


class AuthLogin(BaseModel):
    identifier: str = Field(min_length=2, max_length=64)
    password: str = Field(min_length=8, max_length=128)

    @field_validator('identifier')
    @classmethod
    def normalize_identifier(cls, value: str) -> str:
        return value.strip()


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=10)


class AuthTokens(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = 'bearer'
    access_expires_in_seconds: int


class AuthSession(BaseModel):
    user: UserRead
    tokens: AuthTokens


class UserSettingsUpdate(BaseModel):
    username: str | None = Field(default=None, min_length=2, max_length=32, pattern=USERNAME_REGEX)
    display_name: str | None = Field(default=None, max_length=64)
    current_password: str | None = Field(default=None, min_length=8, max_length=128)
    new_password: str | None = Field(default=None, min_length=8, max_length=128)
    theme_preference: str | None = Field(default=None, pattern=r'^(dark|light|system)$')
    language: str | None = Field(default=None, min_length=2, max_length=16)
    time_format: str | None = Field(default=None, pattern=r'^(12h|24h)$')
    compact_mode: bool | None = None
    show_message_timestamps: bool | None = None

    @field_validator('username')
    @classmethod
    def normalize_username(cls, value: str | None) -> str | None:
        if value is None:
            return None
        return value.strip()

    @field_validator('display_name')
    @classmethod
    def normalize_display_name(cls, value: str | None) -> str | None:
        if value is None:
            return None
        trimmed = value.strip()
        return trimmed if trimmed else None

    @field_validator('theme_preference')
    @classmethod
    def normalize_theme_preference(cls, value: str | None) -> str | None:
        if value is None:
            return None
        return value.strip().lower()

    @field_validator('language')
    @classmethod
    def normalize_language(cls, value: str | None) -> str | None:
        if value is None:
            return None
        trimmed = value.strip()
        return trimmed if trimmed else None

    @field_validator('time_format')
    @classmethod
    def normalize_time_format(cls, value: str | None) -> str | None:
        if value is None:
            return None
        return value.strip().lower()

    @model_validator(mode='after')
    def validate_payload(self) -> 'UserSettingsUpdate':
        payload_fields = self.model_dump(
            exclude_none=True,
            exclude={'current_password'},
        )
        if not payload_fields:
            raise ValueError('At least one settings field must be provided.')

        if 'username' in self.model_fields_set and self.username is None:
            raise ValueError('username cannot be null.')
        if 'theme_preference' in self.model_fields_set and self.theme_preference is None:
            raise ValueError('theme_preference cannot be null.')
        if 'language' in self.model_fields_set and self.language is None:
            raise ValueError('language cannot be null.')
        if 'time_format' in self.model_fields_set and self.time_format is None:
            raise ValueError('time_format cannot be null.')
        if 'compact_mode' in self.model_fields_set and self.compact_mode is None:
            raise ValueError('compact_mode cannot be null.')
        if 'show_message_timestamps' in self.model_fields_set and self.show_message_timestamps is None:
            raise ValueError('show_message_timestamps cannot be null.')

        if self.new_password is not None and not self.current_password:
            raise ValueError('current_password is required to set new_password.')

        return self


class UserDeleteRequest(BaseModel):
    current_password: str = Field(min_length=8, max_length=128)

    @field_validator('current_password')
    @classmethod
    def normalize_current_password(cls, value: str) -> str:
        trimmed = value.strip()
        if not trimmed:
            raise ValueError('current_password is required.')
        return trimmed


class ServerCreate(BaseModel):
    name: str = Field(min_length=2, max_length=100)

    @field_validator('name')
    @classmethod
    def normalize_name(cls, value: str) -> str:
        return value.strip()


class ServerRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    icon_url: str | None
    icon_object_key: str | None
    owner_user_id: UUID


class ServerUpdate(BaseModel):
    name: str = Field(min_length=2, max_length=100)

    @field_validator('name')
    @classmethod
    def normalize_name(cls, value: str) -> str:
        return value.strip()


class ServerMemberRead(BaseModel):
    user_id: UUID
    username: str
    tag: int
    handle: str
    display_name: str | None
    avatar_url: str | None
    role: str
    joined_at: datetime


class ServerOnlineMembersRead(BaseModel):
    total_count: int
    online_count: int
    online_user_ids: list[UUID]


class ServerMemberRoleUpdate(BaseModel):
    role: str = Field(pattern=r'^(admin|member)$')

    @field_validator('role')
    @classmethod
    def normalize_role(cls, value: str) -> str:
        return value.strip().lower()


class ServerOwnershipTransfer(BaseModel):
    new_owner_user_id: UUID


class ServerBanCreate(BaseModel):
    reason: str | None = Field(default=None, max_length=512)

    @field_validator('reason')
    @classmethod
    def normalize_reason(cls, value: str | None) -> str | None:
        if value is None:
            return None
        trimmed = value.strip()
        return trimmed if trimmed else None


class ServerBanRead(BaseModel):
    user_id: UUID
    user_handle: str
    user_display_name: str | None
    banned_by_user_id: UUID
    reason: str | None
    created_at: datetime


class ServerAuditLogRead(BaseModel):
    log_id: int
    action: str
    actor_user_id: UUID
    actor_handle: str | None
    target_user_id: UUID | None
    target_handle: str | None
    target_channel_id: UUID | None
    details: dict[str, Any] | None
    created_at: datetime


class ServerInviteCreate(BaseModel):
    max_uses: int | None = Field(default=None, ge=1, le=100000)
    expires_in_hours: int | None = Field(default=24, ge=1, le=24 * 365)


class ServerInviteRead(BaseModel):
    code: str
    server_id: UUID
    created_by_user_id: UUID
    max_uses: int | None
    use_count: int
    expires_at: datetime | None
    revoked_at: datetime | None
    created_at: datetime


class ServerJoinByInvite(BaseModel):
    code: str = Field(min_length=6, max_length=64)

    @field_validator('code')
    @classmethod
    def normalize_code(cls, value: str) -> str:
        return value.strip()


class ChannelCreate(BaseModel):
    name: str = Field(min_length=1, max_length=64)
    kind: str = Field(default='text', max_length=16)

    @field_validator('name')
    @classmethod
    def normalize_channel_name(cls, value: str) -> str:
        normalized = value.strip().lower().replace(' ', '-')
        if not normalized:
            raise ValueError('Channel name cannot be empty')
        return normalized

    @field_validator('kind')
    @classmethod
    def normalize_kind(cls, value: str) -> str:
        normalized = value.strip().lower()
        if normalized not in {'text', 'voice'}:
            raise ValueError('Channel kind must be text or voice')
        return normalized


class ChannelRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    server_id: UUID
    name: str
    kind: str
    position: int


class VoiceStateUpdate(BaseModel):
    muted: bool = False
    deafened: bool = False


class VoiceStateRead(BaseModel):
    user_id: UUID
    channel_id: UUID
    muted: bool
    deafened: bool
    joined_at: datetime
    handle: str
    display_name: str | None
    avatar_url: str | None


class ChannelUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=64)
    position: int | None = Field(default=None, ge=0, le=1000)

    @field_validator('name')
    @classmethod
    def normalize_channel_name(cls, value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip().lower().replace(' ', '-')
        return normalized if normalized else None

    @model_validator(mode='after')
    def ensure_any_field(self) -> 'ChannelUpdate':
        if self.name is None and self.position is None:
            raise ValueError('At least one field must be provided.')
        return self


class ServerChannelMessageCreate(BaseModel):
    content: str | None = Field(default=None, max_length=4000)
    image_url: str | None = Field(default=None, max_length=2048)
    image_object_key: str | None = Field(default=None, max_length=2048)

    @field_validator('content')
    @classmethod
    def normalize_content(cls, value: str | None) -> str | None:
        if value is None:
            return None
        trimmed = value.strip()
        return trimmed if trimmed else None

    @field_validator('image_url')
    @classmethod
    def normalize_image(cls, value: str | None) -> str | None:
        if value is None:
            return None
        trimmed = value.strip()
        return trimmed if trimmed else None

    @field_validator('image_object_key')
    @classmethod
    def normalize_object_key(cls, value: str | None) -> str | None:
        if value is None:
            return None
        trimmed = value.strip()
        return trimmed if trimmed else None


class ServerChannelMessageEdit(BaseModel):
    content: str = Field(min_length=1, max_length=4000)

    @field_validator('content')
    @classmethod
    def normalize_content(cls, value: str) -> str:
        return value.strip()


class ServerChannelMessageRead(BaseModel):
    message_id: UUID
    channel_id: UUID
    author_user_id: UUID
    content: str | None
    image_url: str | None
    image_object_key: str | None
    created_at: datetime
    edited_at: datetime | None
    deleted_at: datetime | None


class FriendAddRequest(BaseModel):
    handle: str = Field(min_length=7, max_length=37)

    @field_validator('handle')
    @classmethod
    def normalize_handle(cls, value: str) -> str:
        return value.strip()


class FriendRead(BaseModel):
    user_id: UUID
    username: str
    tag: int
    handle: str
    display_name: str | None
    avatar_url: str | None
    created_at: datetime


class DirectMessageChannelRead(BaseModel):
    channel_id: UUID
    peer_user_id: UUID
    peer_handle: str
    peer_display_name: str | None
    peer_avatar_url: str | None


class ImageAssetUpdate(BaseModel):
    image_url: str = Field(min_length=1, max_length=2048)
    image_object_key: str = Field(min_length=1, max_length=2048)

    @field_validator('image_url', 'image_object_key')
    @classmethod
    def normalize_required_text(cls, value: str) -> str:
        trimmed = value.strip()
        if not trimmed:
            raise ValueError('Field cannot be empty.')
        return trimmed


class DirectMessageCreate(BaseModel):
    peer_user_id: UUID


class DirectMessageMessageCreate(BaseModel):
    content: str | None = Field(default=None, max_length=4000)
    image_url: str | None = Field(default=None, max_length=2048)
    image_object_key: str | None = Field(default=None, max_length=2048)

    @field_validator('content')
    @classmethod
    def normalize_content(cls, value: str | None) -> str | None:
        if value is None:
            return None
        trimmed = value.strip()
        return trimmed if trimmed else None

    @field_validator('image_url')
    @classmethod
    def normalize_image(cls, value: str | None) -> str | None:
        if value is None:
            return None
        trimmed = value.strip()
        return trimmed if trimmed else None

    @field_validator('image_object_key')
    @classmethod
    def normalize_object_key(cls, value: str | None) -> str | None:
        if value is None:
            return None
        trimmed = value.strip()
        return trimmed if trimmed else None


class DirectMessageMessageEdit(BaseModel):
    content: str = Field(min_length=1, max_length=4000)

    @field_validator('content')
    @classmethod
    def normalize_content(cls, value: str) -> str:
        return value.strip()


class DirectMessageMessageRead(BaseModel):
    message_id: UUID
    channel_id: UUID
    author_user_id: UUID
    content: str | None
    image_url: str | None
    image_object_key: str | None
    created_at: datetime
    edited_at: datetime | None
    deleted_at: datetime | None


class ImageUploadPrepareRequest(BaseModel):
    content_type: str = Field(min_length=3, max_length=128)
    file_extension: str | None = Field(default=None, min_length=1, max_length=16)

    @field_validator('content_type')
    @classmethod
    def normalize_content_type(cls, value: str) -> str:
        return value.strip().lower()

    @field_validator('file_extension')
    @classmethod
    def normalize_extension(cls, value: str | None) -> str | None:
        if value is None:
            return None
        trimmed = value.strip().lower().lstrip('.')
        return trimmed if trimmed else None


class ImageUploadPrepareResponse(BaseModel):
    upload_url: str
    image_url: str
    image_object_key: str
    expires_in_seconds: int
    required_headers: dict[str, str]


class ImageDirectUploadRequest(BaseModel):
    content_type: str = Field(min_length=3, max_length=128)
    file_extension: str | None = Field(default=None, min_length=1, max_length=16)
    data_base64: str = Field(min_length=1)

    @field_validator('content_type')
    @classmethod
    def normalize_content_type(cls, value: str) -> str:
        return value.strip().lower()

    @field_validator('file_extension')
    @classmethod
    def normalize_extension(cls, value: str | None) -> str | None:
        if value is None:
            return None
        trimmed = value.strip().lower().lstrip('.')
        return trimmed if trimmed else None


class ImageDirectUploadResponse(BaseModel):
    image_url: str
    image_object_key: str
