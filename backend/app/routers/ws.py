import uuid

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from sqlalchemy import select

from app.database import SessionLocal
from app.models import Channel, ChannelMember, ServerMember, User
from app.realtime import realtime_hub
from app.security import decode_token

router = APIRouter(tags=['realtime'])


@router.websocket('/ws')
async def websocket_gateway(websocket: WebSocket) -> None:
    token = websocket.query_params.get('access_token')
    if not token:
        await websocket.close(code=4401)
        return

    try:
        payload = decode_token(token, expected_type='access')
        subject = payload.get('sub')
        user_id = uuid.UUID(subject)
    except Exception:
        await websocket.close(code=4401)
        return

    db = SessionLocal()
    try:
        user = db.get(User, user_id)
        if user is None:
            await websocket.close(code=4401)
            return

        connection_id = await realtime_hub.register(websocket, str(user.id))

        while True:
            message = await websocket.receive_json()
            action = (message.get('action') or '').strip()

            if action == 'subscribe_dm':
                channel_id_raw = (message.get('channel_id') or '').strip()
                if not channel_id_raw:
                    await websocket.send_json(
                        {'type': 'error', 'payload': {'message': 'channel_id is required'}}
                    )
                    continue

                try:
                    channel_id = uuid.UUID(channel_id_raw)
                except ValueError:
                    await websocket.send_json(
                        {'type': 'error', 'payload': {'message': 'channel_id must be uuid'}}
                    )
                    continue

                channel = db.get(Channel, channel_id)
                if channel is None or channel.kind != 'dm' or channel.server_id is not None:
                    await websocket.send_json(
                        {'type': 'error', 'payload': {'message': 'dm channel not found'}}
                    )
                    continue

                membership = db.scalar(
                    select(ChannelMember).where(
                        ChannelMember.channel_id == channel_id,
                        ChannelMember.user_id == user.id,
                    )
                )
                if membership is None:
                    await websocket.send_json(
                        {'type': 'error', 'payload': {'message': 'no access to dm channel'}}
                    )
                    continue

                await realtime_hub.subscribe_dm(connection_id, str(channel_id))
                continue

            if action == 'unsubscribe_dm':
                channel_id_raw = (message.get('channel_id') or '').strip()
                if channel_id_raw:
                    await realtime_hub.unsubscribe_dm(connection_id, channel_id_raw)
                continue

            if action == 'list_subscriptions':
                await websocket.send_json(
                    {
                        'type': 'ws.subscriptions',
                        'payload': realtime_hub.list_all_subscriptions(connection_id),
                    }
                )
                continue

            if action == 'subscribe_server_channel':
                channel_id_raw = (message.get('channel_id') or '').strip()
                if not channel_id_raw:
                    await websocket.send_json(
                        {'type': 'error', 'payload': {'message': 'channel_id is required'}}
                    )
                    continue

                try:
                    channel_id = uuid.UUID(channel_id_raw)
                except ValueError:
                    await websocket.send_json(
                        {'type': 'error', 'payload': {'message': 'channel_id must be uuid'}}
                    )
                    continue

                channel = db.get(Channel, channel_id)
                if (
                    channel is None
                    or channel.server_id is None
                    or channel.kind == 'dm'
                ):
                    await websocket.send_json(
                        {'type': 'error', 'payload': {'message': 'server channel not found'}}
                    )
                    continue

                membership = db.scalar(
                    select(ServerMember).where(
                        ServerMember.server_id == channel.server_id,
                        ServerMember.user_id == user.id,
                    )
                )
                if membership is None:
                    await websocket.send_json(
                        {'type': 'error', 'payload': {'message': 'no access to server channel'}}
                    )
                    continue

                await realtime_hub.subscribe_server_channel(connection_id, str(channel_id))
                continue

            if action == 'unsubscribe_server_channel':
                channel_id_raw = (message.get('channel_id') or '').strip()
                if channel_id_raw:
                    await realtime_hub.unsubscribe_server_channel(connection_id, channel_id_raw)
                continue

            if action == 'subscribe_voice_channel':
                channel_id_raw = (message.get('channel_id') or '').strip()
                if not channel_id_raw:
                    await websocket.send_json(
                        {'type': 'error', 'payload': {'message': 'channel_id is required'}}
                    )
                    continue

                try:
                    channel_id = uuid.UUID(channel_id_raw)
                except ValueError:
                    await websocket.send_json(
                        {'type': 'error', 'payload': {'message': 'channel_id must be uuid'}}
                    )
                    continue

                channel = db.get(Channel, channel_id)
                if (
                    channel is None
                    or channel.server_id is None
                    or channel.kind != 'voice'
                ):
                    await websocket.send_json(
                        {'type': 'error', 'payload': {'message': 'voice channel not found'}}
                    )
                    continue

                membership = db.scalar(
                    select(ServerMember).where(
                        ServerMember.server_id == channel.server_id,
                        ServerMember.user_id == user.id,
                    )
                )
                if membership is None:
                    await websocket.send_json(
                        {'type': 'error', 'payload': {'message': 'no access to voice channel'}}
                    )
                    continue

                await realtime_hub.subscribe_voice_channel(connection_id, str(channel_id))
                continue

            if action == 'unsubscribe_voice_channel':
                channel_id_raw = (message.get('channel_id') or '').strip()
                if channel_id_raw:
                    await realtime_hub.unsubscribe_voice_channel(connection_id, channel_id_raw)
                continue

            if action == 'voice_signal':
                channel_id_raw = (message.get('channel_id') or '').strip()
                signal_type = (message.get('signal_type') or '').strip().lower()
                raw_data = message.get('data')
                if not channel_id_raw:
                    await websocket.send_json(
                        {'type': 'error', 'payload': {'message': 'channel_id is required'}}
                    )
                    continue
                if not signal_type:
                    await websocket.send_json(
                        {'type': 'error', 'payload': {'message': 'signal_type is required'}}
                    )
                    continue

                try:
                    channel_id = uuid.UUID(channel_id_raw)
                except ValueError:
                    await websocket.send_json(
                        {'type': 'error', 'payload': {'message': 'channel_id must be uuid'}}
                    )
                    continue

                channel = db.get(Channel, channel_id)
                if (
                    channel is None
                    or channel.server_id is None
                    or channel.kind != 'voice'
                ):
                    await websocket.send_json(
                        {'type': 'error', 'payload': {'message': 'voice channel not found'}}
                    )
                    continue

                membership = db.scalar(
                    select(ServerMember).where(
                        ServerMember.server_id == channel.server_id,
                        ServerMember.user_id == user.id,
                    )
                )
                if membership is None:
                    await websocket.send_json(
                        {'type': 'error', 'payload': {'message': 'no access to voice channel'}}
                    )
                    continue

                if raw_data is not None and not isinstance(raw_data, dict):
                    await websocket.send_json(
                        {'type': 'error', 'payload': {'message': 'data must be an object'}}
                    )
                    continue

                realtime_hub.publish_voice_signal(
                    channel_id=str(channel.id),
                    server_id=str(channel.server_id),
                    sender_user_id=str(user.id),
                    signal_type=signal_type,
                    data=raw_data if isinstance(raw_data, dict) else {},
                    excluded_connection_id=connection_id,
                )
                await websocket.send_json(
                    {
                        'type': 'voice.signal.sent',
                        'payload': {
                            'channel_id': str(channel.id),
                            'signal_type': signal_type,
                        },
                    }
                )
                continue

            if action == 'presence_ping':
                await websocket.send_json(
                    {
                        'type': 'presence.snapshot',
                        'payload': {
                            'online_user_ids': realtime_hub.online_user_ids(),
                        },
                    }
                )
                continue

            await websocket.send_json(
                {
                    'type': 'error',
                    'payload': {
                        'message': 'Unknown action',
                    },
                }
            )
    except WebSocketDisconnect:
        pass
    finally:
        if 'connection_id' in locals():
            await realtime_hub.unregister(connection_id)
        db.close()
