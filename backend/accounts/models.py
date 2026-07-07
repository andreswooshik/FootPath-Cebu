from django.contrib.auth.models import AbstractUser
from django.db import models


class Roles(models.TextChoices):
    ADMIN = 'ADMIN', 'Admin'
    COACH = 'COACH', 'Coach'
    PLAYER = 'PLAYER', 'Player'
    SCHOOL_STAFF = 'SCHOOL_STAFF', 'School Staff'
    GUARDIAN = 'GUARDIAN', 'Guardian'


class User(AbstractUser):
    # Nullable so createsuperuser still works for the Django admin site;
    # every API user is provisioned with a Firebase UID.
    firebase_uid = models.CharField(
        max_length=128, unique=True, null=True, blank=True, db_index=True
    )
    role = models.CharField(
        max_length=20, choices=Roles.choices, default=Roles.PLAYER
    )

    def __str__(self):
        return f'{self.username} ({self.get_role_display()})'
