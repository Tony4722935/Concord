# Fluxer Alignment Plan

Reference project: https://github.com/fluxerapp/fluxer

## What Fluxer-like means for Concord

To approach Fluxer/Discord quality, Concord should include:
- Persistent data model (users, relationships, servers, channels, messages)
- Real-time messaging sync (WebSocket)
- Channel/server management workflows
- Rich Discord-like navigation and panel hierarchy

## What is now implemented

- Local SQLite persistence in Flutter app (`lib/data/db/concord_database.dart`)
- Core workflows:
  - Add friend
  - Create server
  - Create channel
  - Server settings
  - User settings
- Discord-like three-pane server layout on wide screens

## Next production steps

1. Backend API + central database
- PostgreSQL tables mirroring local SQLite entities
- Auth (JWT + refresh flow)
- CRUD endpoints for friend/server/channel/message operations

2. Realtime layer
- WebSocket gateway for new message/edit/delete events
- Presence updates for friend list

3. Media lifecycle
- Upload image to object storage
- 7-day object cleanup job
- Keep message shell for 1-year retention window

4. Sync architecture
- Keep local SQLite as cache
- Pull/push with backend and conflict handling

## Suggested backend starter stack

- Flutter client (current)
- Backend: NestJS or FastAPI
- DB: PostgreSQL
- Realtime: WebSocket (or Socket.IO)
- Storage: S3-compatible bucket