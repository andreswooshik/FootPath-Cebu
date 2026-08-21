import os
from uuid import uuid4

from django.contrib.auth.models import AbstractUser
from django.core.exceptions import ValidationError
from django.db import models


class Roles(models.TextChoices):
    # The wire/database value remains ADMIN for backward compatibility; the
    # product-facing name is Super Admin in the approved account hierarchy.
    ADMIN = 'ADMIN', 'Super Admin'
    COORDINATOR = 'COORDINATOR', 'Club Coordinator'
    COACH = 'COACH', 'Coach'
    PLAYER = 'PLAYER', 'Player'
    SCHOOL_STAFF = 'SCHOOL_STAFF', 'School Staff'
    GUARDIAN = 'GUARDIAN', 'Guardian'


class ClubTypes(models.TextChoices):
    """API/UI vocabulary mapped onto the existing affiliation fields.

    This is intentionally not another database column: `is_school_affiliated`
    remains the single source of truth for a club's type.
    """

    SCHOOL = 'SCHOOL', 'School Club'
    INDEPENDENT = 'INDEPENDENT', 'Independent Club'


def coach_license_upload_to(instance, filename):
    """Store an uploaded coach license under a random name, keeping only a safe
    extension. Never trust the client-supplied filename (guards against path
    traversal, overwrites, and executable/content-type spoofing)."""
    ext = os.path.splitext(filename)[1].lower()
    if ext not in {'.jpg', '.jpeg', '.png', '.pdf'}:
        ext = ''
    return f'coach-licenses/{uuid4().hex}{ext}'


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

    # Club details maintained by Super Admin. School staff / academic
    # eligibility exist only for school clubs.
    is_school_affiliated = models.BooleanField(default=False)
    school_name = models.CharField(max_length=150, blank=True)
    head_coach_name = models.CharField(max_length=150, blank=True)
    coach_license = models.FileField(
        upload_to=coach_license_upload_to, null=True, blank=True
    )
    cvfa_membership = models.CharField(max_length=80, blank=True)

    class Meta:
        ordering = ['name']

    def __str__(self):
        return self.name

    @property
    def coordinator(self):
        """The owning coordinator (a club has exactly one), or None."""
        return self.members.filter(role=Roles.COORDINATOR).first()

    @property
    def allows_school_staff(self):
        """School-staff accounts and academic eligibility exist only for
        school-affiliated clubs."""
        return self.is_school_affiliated

    @property
    def allows_academic_eligibility(self):
        """Whether status-only academic eligibility applies to this club."""
        return self.is_school_affiliated

    @property
    def club_type(self):
        """Expose the approved SCHOOL/INDEPENDENT label without new storage."""
        return (
            ClubTypes.SCHOOL
            if self.is_school_affiliated
            else ClubTypes.INDEPENDENT
        )


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
    # and for legacy rows created before multi-club tenancy existed. PROTECT
    # prevents deleting an occupied tenant and silently recreating club-less
    # members; clubs are deactivated instead of removed.
    club = models.ForeignKey(
        Club,
        on_delete=models.PROTECT,
        null=True,
        blank=True,
        related_name='members',
    )

    class Meta:
        verbose_name = 'user'
        verbose_name_plural = 'users'
        constraints = [
            models.UniqueConstraint(
                fields=['club'],
                condition=models.Q(role=Roles.COORDINATOR),
                name='one_coordinator_per_club',
            ),
        ]

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

    def clean(self):
        errors = {}
        if self.guardian_id:
            if self.guardian.role != Roles.GUARDIAN:
                errors['guardian'] = 'The guardian account must have the Guardian role.'
            if self.guardian.club_id is None:
                errors['guardian'] = 'The guardian must belong to a club.'
        if self.player_id:
            if self.player.role != Roles.PLAYER:
                errors['player'] = 'The player account must have the Player role.'
            if self.player.club_id is None:
                errors['player'] = 'The player must belong to a club.'
        if (
            self.guardian_id
            and self.player_id
            and self.guardian.club_id != self.player.club_id
        ):
            errors['player'] = 'Guardian and player must belong to the same club.'
        if errors:
            raise ValidationError(errors)

    def __str__(self):
        return f'{self.guardian.email} -> {self.player.email}'
