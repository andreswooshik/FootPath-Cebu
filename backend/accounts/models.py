from django.contrib.auth.models import AbstractUser
from django.db import models


class Roles(models.TextChoices):
    ADMIN = 'ADMIN', 'Admin'
    COORDINATOR = 'COORDINATOR', 'Club Coordinator'
    COACH = 'COACH', 'Coach'
    PLAYER = 'PLAYER', 'Player'
    SCHOOL_STAFF = 'SCHOOL_STAFF', 'School Staff'
    GUARDIAN = 'GUARDIAN', 'Guardian'


class Club(models.Model):
    """A football club/academy — the tenancy boundary.

    Each Club Coordinator owns exactly one club; every player, coach, school
    staff and guardian they provision belongs to it. Isolation is single-sourced
    on `User.club`: a member's club is `user.club`, and a player's club is
    `player.user.club`. ADMIN / Django superusers have no club and are the only
    accounts that see across every club.
    """

    name = models.CharField(max_length=120, unique=True)
    slug = models.SlugField(max_length=140, unique=True)
    # Toggled by a superadmin; an inactive club's coordinator can be frozen out
    # without deleting any data.
    is_active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['name']

    def __str__(self):
        return self.name

    @property
    def coordinator(self):
        """The owning coordinator (a club has exactly one), or None."""
        return self.members.filter(role=Roles.COORDINATOR).first()


class User(AbstractUser):
    # Nullable so createsuperuser still works for the Django admin site;
    # every API user is provisioned with a Firebase UID.
    firebase_uid = models.CharField(
        max_length=128, unique=True, null=True, blank=True, db_index=True
    )
    role = models.CharField(
        max_length=20, choices=Roles.choices, default=Roles.PLAYER
    )
    # The club this account belongs to. Null for ADMIN / superusers (cross-club)
    # and for legacy rows created before multi-club tenancy existed. SET_NULL so
    # removing a club never cascades away its people.
    club = models.ForeignKey(
        Club,
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='members',
    )

    def __str__(self):
        return f'{self.username} ({self.get_role_display()})'


class GuardianLink(models.Model):
    guardian = models.ForeignKey(
        User,
        related_name='guardian_links',
        on_delete=models.CASCADE,
        limit_choices_to={'role': Roles.GUARDIAN},
    )
    player = models.ForeignKey(
        User,
        related_name='player_links',
        on_delete=models.CASCADE,
        limit_choices_to={'role': Roles.PLAYER},
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        unique_together = ('guardian', 'player')

    def __str__(self):
        return f'{self.guardian.email} -> {self.player.email}'
