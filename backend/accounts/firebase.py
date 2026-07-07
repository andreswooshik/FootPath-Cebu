import firebase_admin
from django.conf import settings
from django.core.exceptions import ImproperlyConfigured
from firebase_admin import credentials


def ensure_initialized():
    """Initialize the Firebase Admin SDK exactly once per process."""
    if firebase_admin._apps:
        return
    cred_path = settings.FIREBASE_CREDENTIALS
    if not cred_path.exists():
        raise ImproperlyConfigured(
            f'Firebase service-account file not found at {cred_path}. '
            'Download it from Firebase Console > Project settings > '
            'Service accounts and place it there.'
        )
    firebase_admin.initialize_app(credentials.Certificate(str(cred_path)))
