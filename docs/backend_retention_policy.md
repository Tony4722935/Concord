# Backend Retention Policy Blueprint

This document defines server behavior matching Concord requirements.

## Requirements captured

1. Uploaded files are deleted from server storage after 7 days.
2. Chat messages are retained for 1 year.
3. Users can delete any message they sent at any time.
4. Users can edit messages they sent (Discord-style behavior).
5. Voice chat will be added later.
6. Video sharing is out of scope.

## Suggested data model

`messages`
- `id` (uuid)
- `channel_id` (uuid)
- `author_id` (uuid)
- `type` (`text`, `image`, `system`)
- `content` (text nullable)
- `image_object_key` (text nullable)
- `created_at` (timestamp)
- `edited_at` (timestamp nullable)
- `deleted_at` (timestamp nullable)

`uploads`
- `object_key` (text pk)
- `uploader_id` (uuid)
- `created_at` (timestamp)
- `expires_at` (timestamp = created_at + interval '7 days')

## Write rules

- Send text: insert into `messages(type='text')`.
- Send image:
  - upload object to storage
  - insert `uploads` row with `expires_at`
  - insert `messages(type='image', image_object_key=<key>)`
- Edit message:
  - allow only if `author_id = current_user`
  - update `content`, set `edited_at`
- Delete message:
  - allow only if `author_id = current_user`
  - hard delete (or soft delete + hidden in queries)

## Retention jobs

Run every hour (cron/worker):

1. `upload_gc`
- select `uploads` where `expires_at <= now()`
- delete objects from storage bucket
- set `messages.image_object_key = null` for linked rows
- keep message row for remaining retention window

2. `message_gc`
- delete messages where `created_at < now() - interval '365 days'`

## Query behavior

For chat timeline:
- return messages from last 365 days only
- if image object key is null for image message, return placeholder text like
  `Image removed after 7 days.`

## Security checks

- Users can edit/delete only their own messages.
- Channel membership is required to read/write messages in that channel.
- File upload endpoint must verify allowed MIME type (images only for now).