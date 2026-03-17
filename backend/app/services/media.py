from collections.abc import Iterable
from urllib.parse import unquote, urlparse

from app.config import settings
from app.services.storage import get_storage_service


def resolve_storage_object_key(image_object_key: str | None, image_url: str | None) -> str | None:
    if image_object_key:
        normalized = image_object_key.strip()
        if normalized:
            return normalized

    if not image_url:
        return None

    raw_url = image_url.strip()
    if not raw_url:
        return None

    parsed = urlparse(raw_url)
    path = parsed.path or raw_url
    prefixes = [
        f'{settings.api_prefix.rstrip("/")}/uploads/files/',
        '/uploads/files/',
    ]

    for prefix in prefixes:
        index = path.find(prefix)
        if index < 0:
            continue
        candidate = unquote(path[index + len(prefix) :].lstrip('/'))
        if candidate:
            return candidate

    return None


def resolve_message_object_key(image_object_key: str | None, image_url: str | None) -> str | None:
    return resolve_storage_object_key(image_object_key, image_url)


def collect_message_object_keys(rows: Iterable[tuple[str | None, str | None]]) -> set[str]:
    object_keys: set[str] = set()
    for image_object_key, image_url in rows:
        resolved = resolve_message_object_key(image_object_key, image_url)
        if resolved:
            object_keys.add(resolved)
    return object_keys


def delete_storage_objects(object_keys: Iterable[str]) -> int:
    unique_keys = sorted({key.strip() for key in object_keys if key and key.strip()})
    if not unique_keys:
        return 0

    storage = get_storage_service()
    for key in unique_keys:
        storage.delete_object(key)

    return len(unique_keys)
