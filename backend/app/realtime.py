import asyncio
import logging
import threading
import uuid
from collections.abc import Coroutine
from dataclasses import dataclass, field
from datetime import datetime, timezone

from fastapi import WebSocket

logger = logging.getLogger('concord-realtime')


@dataclass
class ConnectionState:
    connection_id: str
    user_id: str
    websocket: WebSocket
    subscribed_dm_ids: set[str] = field(default_factory=set)
    subscribed_server_channel_ids: set[str] = field(default_factory=set)
    subscribed_voice_channel_ids: set[str] = field(default_factory=set)


class RealtimeHub:
    def __init__(self) -> None:
        self._lock = threading.RLock()
        self._loop: asyncio.AbstractEventLoop | None = None
        self._connections: dict[str, ConnectionState] = {}
        self._dm_subscribers: dict[str, set[str]] = {}
        self._server_channel_subscribers: dict[str, set[str]] = {}
        self._voice_channel_subscribers: dict[str, set[str]] = {}
        self._user_connections: dict[str, set[str]] = {}

    def set_loop(self, loop: asyncio.AbstractEventLoop) -> None:
        with self._lock:
            self._loop = loop

    async def register(self, websocket: WebSocket, user_id: str) -> str:
        await websocket.accept()

        connection_id = str(uuid.uuid4())
        became_online = False

        with self._lock:
            self._connections[connection_id] = ConnectionState(
                connection_id=connection_id,
                user_id=user_id,
                websocket=websocket,
            )
            user_conn_set = self._user_connections.setdefault(user_id, set())
            if not user_conn_set:
                became_online = True
            user_conn_set.add(connection_id)

        await self._safe_send(
            websocket,
            {
                'type': 'ws.ready',
                'payload': {
                    'connection_id': connection_id,
                    'user_id': user_id,
                    'timestamp': self._now_iso(),
                },
            },
        )

        if became_online:
            self.publish_presence_update(user_id=user_id, status='online')

        return connection_id

    async def unregister(self, connection_id: str) -> None:
        became_offline_user_id: str | None = None

        with self._lock:
            connection = self._connections.pop(connection_id, None)
            if connection is None:
                return

            for dm_id in connection.subscribed_dm_ids:
                subscribers = self._dm_subscribers.get(dm_id)
                if subscribers is not None:
                    subscribers.discard(connection_id)
                    if not subscribers:
                        self._dm_subscribers.pop(dm_id, None)

            for channel_id in connection.subscribed_server_channel_ids:
                subscribers = self._server_channel_subscribers.get(channel_id)
                if subscribers is not None:
                    subscribers.discard(connection_id)
                    if not subscribers:
                        self._server_channel_subscribers.pop(channel_id, None)

            for channel_id in connection.subscribed_voice_channel_ids:
                subscribers = self._voice_channel_subscribers.get(channel_id)
                if subscribers is not None:
                    subscribers.discard(connection_id)
                    if not subscribers:
                        self._voice_channel_subscribers.pop(channel_id, None)

            user_set = self._user_connections.get(connection.user_id)
            if user_set is not None:
                user_set.discard(connection_id)
                if not user_set:
                    self._user_connections.pop(connection.user_id, None)
                    became_offline_user_id = connection.user_id

        if became_offline_user_id is not None:
            self.publish_presence_update(user_id=became_offline_user_id, status='offline')

    async def subscribe_dm(self, connection_id: str, dm_channel_id: str) -> bool:
        with self._lock:
            connection = self._connections.get(connection_id)
            if connection is None:
                return False

            connection.subscribed_dm_ids.add(dm_channel_id)
            self._dm_subscribers.setdefault(dm_channel_id, set()).add(connection_id)
            websocket = connection.websocket

        await self._safe_send(
            websocket,
            {
                'type': 'dm.subscribed',
                'payload': {
                    'channel_id': dm_channel_id,
                    'timestamp': self._now_iso(),
                },
            },
        )
        return True

    async def unsubscribe_dm(self, connection_id: str, dm_channel_id: str) -> bool:
        with self._lock:
            connection = self._connections.get(connection_id)
            if connection is None:
                return False

            connection.subscribed_dm_ids.discard(dm_channel_id)
            subscribers = self._dm_subscribers.get(dm_channel_id)
            if subscribers is not None:
                subscribers.discard(connection_id)
                if not subscribers:
                    self._dm_subscribers.pop(dm_channel_id, None)

            websocket = connection.websocket

        await self._safe_send(
            websocket,
            {
                'type': 'dm.unsubscribed',
                'payload': {
                    'channel_id': dm_channel_id,
                    'timestamp': self._now_iso(),
                },
            },
        )
        return True

    async def subscribe_server_channel(self, connection_id: str, channel_id: str) -> bool:
        with self._lock:
            connection = self._connections.get(connection_id)
            if connection is None:
                return False

            connection.subscribed_server_channel_ids.add(channel_id)
            self._server_channel_subscribers.setdefault(channel_id, set()).add(connection_id)
            websocket = connection.websocket

        await self._safe_send(
            websocket,
            {
                'type': 'server_channel.subscribed',
                'payload': {
                    'channel_id': channel_id,
                    'timestamp': self._now_iso(),
                },
            },
        )
        return True

    async def unsubscribe_server_channel(self, connection_id: str, channel_id: str) -> bool:
        with self._lock:
            connection = self._connections.get(connection_id)
            if connection is None:
                return False

            connection.subscribed_server_channel_ids.discard(channel_id)
            subscribers = self._server_channel_subscribers.get(channel_id)
            if subscribers is not None:
                subscribers.discard(connection_id)
                if not subscribers:
                    self._server_channel_subscribers.pop(channel_id, None)

            websocket = connection.websocket

        await self._safe_send(
            websocket,
            {
                'type': 'server_channel.unsubscribed',
                'payload': {
                    'channel_id': channel_id,
                    'timestamp': self._now_iso(),
                },
            },
        )
        return True

    async def subscribe_voice_channel(self, connection_id: str, channel_id: str) -> bool:
        with self._lock:
            connection = self._connections.get(connection_id)
            if connection is None:
                return False

            connection.subscribed_voice_channel_ids.add(channel_id)
            self._voice_channel_subscribers.setdefault(channel_id, set()).add(connection_id)
            websocket = connection.websocket

        await self._safe_send(
            websocket,
            {
                'type': 'voice.subscribed',
                'payload': {
                    'channel_id': channel_id,
                    'timestamp': self._now_iso(),
                },
            },
        )
        return True

    async def unsubscribe_voice_channel(self, connection_id: str, channel_id: str) -> bool:
        with self._lock:
            connection = self._connections.get(connection_id)
            if connection is None:
                return False

            connection.subscribed_voice_channel_ids.discard(channel_id)
            subscribers = self._voice_channel_subscribers.get(channel_id)
            if subscribers is not None:
                subscribers.discard(connection_id)
                if not subscribers:
                    self._voice_channel_subscribers.pop(channel_id, None)

            websocket = connection.websocket

        await self._safe_send(
            websocket,
            {
                'type': 'voice.unsubscribed',
                'payload': {
                    'channel_id': channel_id,
                    'timestamp': self._now_iso(),
                },
            },
        )
        return True

    def list_subscriptions(self, connection_id: str) -> list[str]:
        with self._lock:
            connection = self._connections.get(connection_id)
            if connection is None:
                return []
            return sorted(connection.subscribed_dm_ids)

    def list_all_subscriptions(self, connection_id: str) -> dict[str, list[str]]:
        with self._lock:
            connection = self._connections.get(connection_id)
            if connection is None:
                return {'dm_channels': [], 'server_channels': [], 'voice_channels': []}
            return {
                'dm_channels': sorted(connection.subscribed_dm_ids),
                'server_channels': sorted(connection.subscribed_server_channel_ids),
                'voice_channels': sorted(connection.subscribed_voice_channel_ids),
            }

    def online_user_ids(self) -> list[str]:
        with self._lock:
            return sorted(self._user_connections.keys())

    def publish_dm_event(self, dm_channel_id: str, event_type: str, payload: dict) -> None:
        self._schedule(
            self._publish_to_dm_subscribers(
                dm_channel_id=dm_channel_id,
                event_type=event_type,
                payload=payload,
            )
        )

    def publish_server_channel_event(self, channel_id: str, event_type: str, payload: dict) -> None:
        self._schedule(
            self._publish_to_server_channel_subscribers(
                channel_id=channel_id,
                event_type=event_type,
                payload=payload,
            )
        )

    def publish_presence_update(self, user_id: str, status: str) -> None:
        self._schedule(
            self._broadcast(
                {
                    'type': 'presence.update',
                    'payload': {
                        'user_id': user_id,
                        'status': status,
                        'timestamp': self._now_iso(),
                    },
                }
            )
        )

    def publish_voice_signal(
        self,
        *,
        channel_id: str,
        server_id: str,
        sender_user_id: str,
        signal_type: str,
        data: dict | None,
        excluded_connection_id: str | None = None,
    ) -> None:
        self._schedule(
            self._publish_to_voice_channel_subscribers(
                channel_id=channel_id,
                message={
                    'type': 'voice.signal',
                    'payload': {
                        'channel_id': channel_id,
                        'server_id': server_id,
                        'sender_user_id': sender_user_id,
                        'signal_type': signal_type,
                        'data': data or {},
                        'timestamp': self._now_iso(),
                    },
                },
                excluded_connection_id=excluded_connection_id,
            )
        )

    def _schedule(self, coro: asyncio.Future | Coroutine) -> None:
        with self._lock:
            loop = self._loop

        if loop is None:
            logger.warning('Realtime loop is not set; dropping event.')
            return

        asyncio.run_coroutine_threadsafe(coro, loop)

    async def _publish_to_dm_subscribers(self, dm_channel_id: str, event_type: str, payload: dict) -> None:
        with self._lock:
            subscriber_ids = list(self._dm_subscribers.get(dm_channel_id, set()))
            websockets = [
                self._connections[conn_id].websocket
                for conn_id in subscriber_ids
                if conn_id in self._connections
            ]

        message = {
            'type': event_type,
            'payload': {
                'channel_id': dm_channel_id,
                **payload,
            },
        }

        await asyncio.gather(*(self._safe_send(ws, message) for ws in websockets), return_exceptions=True)

    async def _publish_to_server_channel_subscribers(
        self,
        channel_id: str,
        event_type: str,
        payload: dict,
    ) -> None:
        with self._lock:
            subscriber_ids = list(self._server_channel_subscribers.get(channel_id, set()))
            websockets = [
                self._connections[conn_id].websocket
                for conn_id in subscriber_ids
                if conn_id in self._connections
            ]

        message = {
            'type': event_type,
            'payload': {
                'channel_id': channel_id,
                **payload,
            },
        }

        await asyncio.gather(*(self._safe_send(ws, message) for ws in websockets), return_exceptions=True)

    async def _broadcast(self, message: dict) -> None:
        with self._lock:
            websockets = [conn.websocket for conn in self._connections.values()]

        await asyncio.gather(*(self._safe_send(ws, message) for ws in websockets), return_exceptions=True)

    async def _publish_to_voice_channel_subscribers(
        self,
        *,
        channel_id: str,
        message: dict,
        excluded_connection_id: str | None = None,
    ) -> None:
        with self._lock:
            subscriber_ids = list(self._voice_channel_subscribers.get(channel_id, set()))
            websockets = []
            for conn_id in subscriber_ids:
                if excluded_connection_id is not None and conn_id == excluded_connection_id:
                    continue
                connection = self._connections.get(conn_id)
                if connection is not None:
                    websockets.append(connection.websocket)

        await asyncio.gather(*(self._safe_send(ws, message) for ws in websockets), return_exceptions=True)

    async def _safe_send(self, websocket: WebSocket, message: dict) -> None:
        try:
            await websocket.send_json(message)
        except Exception:
            logger.debug('Failed sending websocket message; client likely disconnected.', exc_info=True)

    def _now_iso(self) -> str:
        return datetime.now(timezone.utc).isoformat()


realtime_hub = RealtimeHub()
