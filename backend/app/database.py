from collections.abc import Generator

from sqlalchemy import create_engine, inspect, text
from sqlalchemy.orm import DeclarativeBase, Session, sessionmaker

from app.config import settings


class Base(DeclarativeBase):
    pass


engine = create_engine(settings.database_url, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False, expire_on_commit=False)


def get_db() -> Generator[Session, None, None]:
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


def run_migrations() -> None:
    inspector = inspect(engine)

    if 'users' in inspector.get_table_names():
        columns = {column['name'] for column in inspector.get_columns('users')}
        if 'password_hash' not in columns:
            with engine.begin() as connection:
                connection.execute(text('ALTER TABLE users ADD COLUMN password_hash VARCHAR(255);'))
        if 'is_platform_admin' not in columns:
            with engine.begin() as connection:
                connection.execute(
                    text('ALTER TABLE users ADD COLUMN is_platform_admin BOOLEAN NOT NULL DEFAULT FALSE;')
                )
        if 'theme_preference' not in columns:
            with engine.begin() as connection:
                connection.execute(
                    text("ALTER TABLE users ADD COLUMN theme_preference VARCHAR(16) NOT NULL DEFAULT 'dark';")
                )
        if 'language' not in columns:
            with engine.begin() as connection:
                connection.execute(
                    text("ALTER TABLE users ADD COLUMN language VARCHAR(16) NOT NULL DEFAULT 'en-US';")
                )
        if 'time_format' not in columns:
            with engine.begin() as connection:
                connection.execute(
                    text("ALTER TABLE users ADD COLUMN time_format VARCHAR(8) NOT NULL DEFAULT '24h';")
                )
        if 'compact_mode' not in columns:
            with engine.begin() as connection:
                connection.execute(
                    text('ALTER TABLE users ADD COLUMN compact_mode BOOLEAN NOT NULL DEFAULT FALSE;')
                )
        if 'show_message_timestamps' not in columns:
            with engine.begin() as connection:
                connection.execute(
                    text(
                        'ALTER TABLE users ADD COLUMN show_message_timestamps BOOLEAN NOT NULL DEFAULT TRUE;'
                    )
                )
        if 'avatar_url' not in columns:
            with engine.begin() as connection:
                connection.execute(text('ALTER TABLE users ADD COLUMN avatar_url TEXT;'))
        if 'avatar_object_key' not in columns:
            with engine.begin() as connection:
                connection.execute(text('ALTER TABLE users ADD COLUMN avatar_object_key TEXT;'))

    if 'servers' in inspector.get_table_names():
        columns = {column['name'] for column in inspector.get_columns('servers')}
        if 'icon_url' not in columns:
            with engine.begin() as connection:
                connection.execute(text('ALTER TABLE servers ADD COLUMN icon_url TEXT;'))
        if 'icon_object_key' not in columns:
            with engine.begin() as connection:
                connection.execute(text('ALTER TABLE servers ADD COLUMN icon_object_key TEXT;'))

    if 'channels' in inspector.get_table_names():
        columns = {column['name']: column for column in inspector.get_columns('channels')}
        server_id_column = columns.get('server_id')
        if server_id_column and not server_id_column.get('nullable', False):
            with engine.begin() as connection:
                connection.execute(text('ALTER TABLE channels ALTER COLUMN server_id DROP NOT NULL;'))

    if 'messages' in inspector.get_table_names():
        columns = {column['name'] for column in inspector.get_columns('messages')}
        if 'image_object_key' not in columns:
            with engine.begin() as connection:
                connection.execute(text('ALTER TABLE messages ADD COLUMN image_object_key TEXT;'))
