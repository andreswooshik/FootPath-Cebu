from django.apps import AppConfig


class AcademyConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'academy'

    def ready(self):
        # Register the eligibility-change push signals (signals.py) so they
        # fire for every write path: admin site, console, or API.
        from . import signals  # noqa: F401
