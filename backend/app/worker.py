import argparse
import logging
import time
from datetime import datetime, timezone

from app.config import settings
from app.database import SessionLocal
from app.retention import run_retention_sweep

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s | %(levelname)s | %(message)s',
)
logger = logging.getLogger('concord-retention-worker')


def run_once() -> None:
    db = SessionLocal()
    try:
        summary = run_retention_sweep(db, now=datetime.now(timezone.utc))
        logger.info(
            'Retention sweep complete: messages_deleted=%s images_expired=%s objects_deleted=%s object_delete_failures=%s',
            summary.messages_deleted,
            summary.images_expired,
            summary.objects_deleted,
            summary.object_delete_failures,
        )
    finally:
        db.close()


def main() -> None:
    parser = argparse.ArgumentParser(description='Concord retention worker')
    parser.add_argument('--once', action='store_true', help='Run one sweep and exit')
    args = parser.parse_args()

    if args.once:
        run_once()
        return

    interval_seconds = max(1, settings.retention_sweep_minutes) * 60
    logger.info('Retention worker started (interval=%s minutes)', settings.retention_sweep_minutes)

    while True:
        try:
            run_once()
        except Exception:
            logger.exception('Retention sweep failed')

        time.sleep(interval_seconds)


if __name__ == '__main__':
    main()
