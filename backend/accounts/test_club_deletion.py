from datetime import date

from django.contrib.admin.sites import AdminSite
from django.db.models.deletion import ProtectedError
from django.test import TestCase

from academy.models import AgeTier, TrainingSession

from .admin import ClubAdmin
from .models import Club, Roles, User


class ClubDeletionProtectionTests(TestCase):
    def test_member_reference_blocks_model_delete(self):
        club = Club.objects.create(name='Member Tenant', slug='member-tenant')
        member = User.objects.create(
            username='member@tenant.test',
            email='member@tenant.test',
            role=Roles.COACH,
            club=club,
        )

        with self.assertRaises(ProtectedError):
            club.delete()

        member.refresh_from_db()
        self.assertEqual(member.club_id, club.pk)
        self.assertTrue(Club.objects.filter(pk=club.pk).exists())

    def test_session_reference_blocks_queryset_delete(self):
        club = Club.objects.create(name='Calendar Tenant', slug='calendar-tenant')
        session = TrainingSession.objects.create(
            title='Protected calendar',
            date=date.today(),
            age_tiers=[AgeTier.DEVELOPMENT],
            club=club,
        )

        with self.assertRaises(ProtectedError):
            Club.objects.filter(pk=club.pk).delete()

        session.refresh_from_db()
        self.assertEqual(session.club_id, club.pk)
        self.assertTrue(Club.objects.filter(pk=club.pk).exists())

    def test_club_admin_disables_deletion_in_favor_of_deactivation(self):
        model_admin = ClubAdmin(Club, AdminSite())

        self.assertFalse(model_admin.has_delete_permission(request=None))
