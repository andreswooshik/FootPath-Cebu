import logging

from django.apps import AppConfig

logger = logging.getLogger(__name__)


class AccountsConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'accounts'

    def ready(self):
        # Initialize Firebase eagerly so the first request doesn't pay the
        # cost, but let the server boot without credentials (migrations,
        # health checks) — token verification will fail loudly instead.
        from .firebase import ensure_initialized

        try:
            ensure_initialized()
        except Exception as exc:  # noqa: BLE001 - warn, don't block startup
            logger.warning('Firebase Admin SDK not initialized: %s', exc)
