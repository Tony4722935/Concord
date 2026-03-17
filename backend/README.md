# Concord Backend (Docker)

This backend is the first production foundation for Concord.

## Implemented now

- PostgreSQL persistence
- UUID primary keys for:
  - users
  - servers
  - channels
  - messages
- Background retention worker (`concord-worker`) for:
  - 1-year message retention
  - 7-day image expiry cleanup
- Discord-style user handle format: `username#1234`
  - unique by (`username`, `tag`)
  - tag is auto-assigned from `0001` to `9999`
- Core API endpoints:
  - register/login/refresh auth
  - current user profile/settings (`/auth/me`)
  - websocket realtime gateway (`/ws`)
  - friend management (`/friends`)
  - direct messages (`/dms`)
  - server membership/roles/invites (`/servers`)
  - platform admin visibility mode (global server/user access with hidden presence)
  - create user
  - lookup user by handle
  - create/list servers
  - transfer ownership and leave server
  - moderation (kick, ban, unban)
  - server audit logs
  - self-host image upload endpoint (`/uploads/image-direct`)
  - optional S3 presign upload endpoint (`/uploads/presign-image`)
  - create/list server channels
  - update/delete server
  - update/reorder/delete server channels
  - create/revoke invite codes and join by invite

## Run with Docker

From repository root:

```bash
cp .env.backend.example .env.backend
docker compose --env-file .env.backend -f docker-compose.backend.yml up -d --build
```

If port `5432` or `8000` is already in use on your server, override them:

```bash
POSTGRES_PORT=5433 API_PORT=8001 docker compose --env-file .env.backend -f docker-compose.backend.yml up -d --build
```

Health check:

```bash
curl http://localhost:8000/healthz
```

Important for production:
- set a strong `JWT_SECRET` in `.env.backend`
- lock down `CORS_ALLOW_ORIGINS`
- tune retention env vars if needed:
  - `MESSAGE_RETENTION_DAYS`
  - `UPLOAD_RETENTION_DAYS`
  - `RETENTION_SWEEP_MINUTES`
- for S3-compatible uploads, configure:
  - `S3_ENDPOINT_URL`
  - `S3_ACCESS_KEY_ID`
  - `S3_SECRET_ACCESS_KEY`
  - `S3_BUCKET`
  - `S3_PUBLIC_BASE_URL` (optional)
  - `S3_PRESIGN_EXPIRY_SECONDS`
  - `S3_USE_PATH_STYLE`
  - `S3_PREFIX`
  - `UPLOAD_ALLOWED_CONTENT_TYPES`

## API quick start

### 1) Register

```bash
curl -X POST http://localhost:8000/v1/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"tony","password":"StrongPass123","display_name":"Tony"}'
```

Response includes:
- `user` (`id`, `username`, `tag`, `handle`)
- `tokens` (`access_token`, `refresh_token`)

### 2) Login

```bash
curl -X POST http://localhost:8000/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"identifier":"tony#0001","password":"StrongPass123"}'
```

### 3) Refresh token

```bash
curl -X POST http://localhost:8000/v1/auth/refresh \
  -H "Content-Type: application/json" \
  -d '{"refresh_token":"<REFRESH_TOKEN>"}'
```

### 4) Current user (`/me`)

```bash
curl http://localhost:8000/v1/auth/me \
  -H "Authorization: Bearer <ACCESS_TOKEN>"
```

### 4b) Update current user settings

```bash
curl -X PATCH http://localhost:8000/v1/auth/me \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -d '{"display_name":"Tony Stark"}'

curl -X PATCH http://localhost:8000/v1/auth/me \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -d '{"username":"tony_new"}'

curl -X PATCH http://localhost:8000/v1/auth/me \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -d '{"current_password":"StrongPass123","new_password":"NewStrongPass123"}'
```

### 5) Create user (admin/system utility endpoint)

```bash
curl -X POST http://localhost:8000/v1/users \
  -H "Content-Type: application/json" \
  -d '{"username":"bot_ops","display_name":"Ops Bot","password":"StrongPass123"}'
```

### 6) Lookup by handle (requires access token)

```bash
curl "http://localhost:8000/v1/users/lookup?handle=tony%230001" \
  -H "Authorization: Bearer <ACCESS_TOKEN>"
```

Platform-admin stealth rule:
- non-platform users cannot lookup platform admin accounts
- returns `404` for hidden platform admin handles

### 6b) Platform admin: list all users

```bash
curl "http://localhost:8000/v1/users?limit=500&offset=0" \
  -H "Authorization: Bearer <ACCESS_TOKEN>"
```

Platform admin behavior:
- can see all servers and all users globally
- does not appear in server member lists unless explicitly added as member
- non-platform users cannot add platform admin as friend
- non-platform users cannot initiate DM to platform admin
- platform admin can initiate DM to any user

### 7) Create server

```bash
curl -X POST http://localhost:8000/v1/servers \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -d '{"name":"Concord HQ"}'
```

### 8) Create channel

```bash
curl -X POST http://localhost:8000/v1/servers/<SERVER_UUID>/channels \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -d '{"name":"announcements","kind":"text"}'
```

### 9) List channels

```bash
curl http://localhost:8000/v1/servers/<SERVER_UUID>/channels \
  -H "Authorization: Bearer <ACCESS_TOKEN>"
```

### 9b) Server channel messaging

```bash
curl -X POST http://localhost:8000/v1/servers/<SERVER_UUID>/channels/<CHANNEL_UUID>/messages \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -d '{"content":"hello server channel","image_url":"https://...","image_object_key":"images/.../file.png"}'

curl http://localhost:8000/v1/servers/<SERVER_UUID>/channels/<CHANNEL_UUID>/messages \
  -H "Authorization: Bearer <ACCESS_TOKEN>"
```

### 9c) Server settings (rename/delete server, rename/reorder/delete channels)

```bash
curl -X PATCH http://localhost:8000/v1/servers/<SERVER_UUID> \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -d '{"name":"Concord HQ Renamed"}'

curl -X PATCH http://localhost:8000/v1/servers/<SERVER_UUID>/channels/<CHANNEL_UUID> \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -d '{"name":"release-notes","position":0}'

curl -X DELETE http://localhost:8000/v1/servers/<SERVER_UUID>/channels/<CHANNEL_UUID> \
  -H "Authorization: Bearer <ACCESS_TOKEN>"

curl -X DELETE http://localhost:8000/v1/servers/<SERVER_UUID> \
  -H "Authorization: Bearer <ACCESS_TOKEN>"
```

### 10) Add friend by handle (requires access token)

```bash
curl -X POST http://localhost:8000/v1/friends/add \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -d '{"handle":"alex#0001"}'
```

### 11) List friends

```bash
curl http://localhost:8000/v1/friends \
  -H "Authorization: Bearer <ACCESS_TOKEN>"
```

### 12) Open DM with friend

```bash
curl -X POST http://localhost:8000/v1/dms/open \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -d '{"peer_user_id":"<FRIEND_USER_UUID>"}'
```

### 13) Send DM message

```bash
curl -X POST http://localhost:8000/v1/dms/<DM_CHANNEL_UUID>/messages \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -d '{"content":"hello from concord"}'
```

### 14) Edit/Delete your DM message

```bash
curl -X PATCH http://localhost:8000/v1/dms/<DM_CHANNEL_UUID>/messages/<MESSAGE_UUID> \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -d '{"content":"edited text"}'

curl -X DELETE http://localhost:8000/v1/dms/<DM_CHANNEL_UUID>/messages/<MESSAGE_UUID> \
  -H "Authorization: Bearer <ACCESS_TOKEN>"
```

### 15) Create invite and join server

```bash
curl -X POST http://localhost:8000/v1/servers/<SERVER_UUID>/invites \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -d '{"max_uses":10,"expires_in_hours":24}'

curl -X POST http://localhost:8000/v1/servers/join-by-invite \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -d '{"code":"<INVITE_CODE>"}'
```

### 16) List members and promote/demote

```bash
curl http://localhost:8000/v1/servers/<SERVER_UUID>/members \
  -H "Authorization: Bearer <ACCESS_TOKEN>"

curl -X PATCH http://localhost:8000/v1/servers/<SERVER_UUID>/members/<USER_UUID>/role \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -d '{"role":"admin"}'
```

### 16b) Transfer ownership and leave server

```bash
curl -X POST http://localhost:8000/v1/servers/<SERVER_UUID>/transfer-ownership \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -d '{"new_owner_user_id":"<USER_UUID>"}'

curl -X POST http://localhost:8000/v1/servers/<SERVER_UUID>/leave \
  -H "Authorization: Bearer <ACCESS_TOKEN>"
```

### 16c) Moderation (kick, ban, unban)

```bash
curl -X POST http://localhost:8000/v1/servers/<SERVER_UUID>/members/<USER_UUID>/kick \
  -H "Authorization: Bearer <ACCESS_TOKEN>"

curl http://localhost:8000/v1/servers/<SERVER_UUID>/bans \
  -H "Authorization: Bearer <ACCESS_TOKEN>"

curl -X POST http://localhost:8000/v1/servers/<SERVER_UUID>/bans/<USER_UUID> \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -d '{"reason":"spam"}'

curl -X DELETE http://localhost:8000/v1/servers/<SERVER_UUID>/bans/<USER_UUID> \
  -H "Authorization: Bearer <ACCESS_TOKEN>"
```

### 16d) Server audit logs

```bash
curl "http://localhost:8000/v1/servers/<SERVER_UUID>/audit-logs?limit=100" \
  -H "Authorization: Bearer <ACCESS_TOKEN>"

# Cursor pagination
curl "http://localhost:8000/v1/servers/<SERVER_UUID>/audit-logs?limit=100&cursor_log_id=<LAST_LOG_ID>"

# Filters
curl "http://localhost:8000/v1/servers/<SERVER_UUID>/audit-logs?limit=100&action=member.ban"
curl "http://localhost:8000/v1/servers/<SERVER_UUID>/audit-logs?limit=100&actor_user_id=<USER_UUID>"
curl "http://localhost:8000/v1/servers/<SERVER_UUID>/audit-logs?limit=100&target_user_id=<USER_UUID>"
```

Response header:
- `X-Next-Cursor` (use this as `cursor_log_id` for next page)

### 16e) Image upload presign

```bash
curl -X POST http://localhost:8000/v1/uploads/presign-image \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -d '{"content_type":"image/png","file_extension":"png"}'
```

Upload flow:
- call presign endpoint
- upload bytes to returned `upload_url` with `required_headers`
- send message with `image_url` and `image_object_key`

### 16f) Self-host image direct upload

```bash
curl -X POST http://localhost:8000/v1/uploads/image-direct \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ACCESS_TOKEN>" \
  -d '{"content_type":"image/png","file_extension":"png","data_base64":"<BASE64_BYTES>"}'
```

Self-host behavior:
- works without S3 configuration
- files are stored in `LOCAL_UPLOAD_DIR` (default `/data/uploads`)
- files are served by backend at `/v1/uploads/files/<object_key>`

### 17) Realtime websocket

Connect:

```text
ws://localhost:8000/v1/ws?access_token=<ACCESS_TOKEN>
```

Client actions:
- `{"action":"subscribe_dm","channel_id":"<DM_CHANNEL_UUID>"}`
- `{"action":"unsubscribe_dm","channel_id":"<DM_CHANNEL_UUID>"}`
- `{"action":"subscribe_server_channel","channel_id":"<SERVER_CHANNEL_UUID>"}`
- `{"action":"unsubscribe_server_channel","channel_id":"<SERVER_CHANNEL_UUID>"}`
- `{"action":"subscribe_voice_channel","channel_id":"<VOICE_CHANNEL_UUID>"}`
- `{"action":"unsubscribe_voice_channel","channel_id":"<VOICE_CHANNEL_UUID>"}`
- `{"action":"voice_signal","channel_id":"<VOICE_CHANNEL_UUID>","signal_type":"offer|answer|candidate|join|leave|state_update","data":{...}}`
- `{"action":"list_subscriptions"}`
- `{"action":"presence_ping"}`

Server events:
- `ws.ready`
- `presence.update`
- `dm.subscribed` / `dm.unsubscribed`
- `dm.message.created`
- `dm.message.edited`
- `dm.message.deleted`
- `server_channel.subscribed` / `server_channel.unsubscribed`
- `voice.subscribed` / `voice.unsubscribed`
- `voice.signal`
- `voice.signal.sent`
- `server.message.created`
- `server.message.edited`
- `server.message.deleted`

Example `UserRead` payload:

```json
{
  "id": "7fca8f15-06ee-4c4c-9a75-c0be2f679f34",
  "username": "tony",
  "tag": 1,
  "handle": "tony#0001",
  "display_name": "Tony"
}
```

## Retention worker

The worker runs continuously in Docker (`concord-worker`) and sweeps at `RETENTION_SWEEP_MINUTES`.
For image messages, the worker attempts S3 object deletion by `image_object_key` before clearing image metadata.

Run one sweep manually:

```bash
docker compose --env-file .env.backend -f docker-compose.backend.yml run --rm concord-worker python -m app.worker --once
```

## Notes

- Tables are auto-created on service startup for now.
- Next step should be adding migration tooling (Alembic) before production rollout.
