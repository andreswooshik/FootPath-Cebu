"""Tests for the coordinator & school-staff web portal.

Covers signup + approval gating, session-auth role access control, club-scoped
account creation (players/coaches/staff/guardians), tenant isolation, and the
staff eligibility flow. Firebase is mocked wherever an app user (player / coach
/ guardian) is provisioned, so the suite runs offline like the rest.
"""
from datetime import date
from unittest.mock import Mock, patch

from django.contrib.admin.sites import site
from django.test import TestCase
from django.urls import reverse
from firebase_admin import auth as firebase_auth

from academy.models import Eligibility, EligibilityHistory, PlayerProfile
from accounts.admin import CustomUserAdmin
from accounts.models import Club, GuardianLink, Roles, User
from accounts.services import provision_web_user

from .services import register_coordinator

_PASSWORD = 'Str0ng!passphrase9'

# The three patches every app-user (Firebase) provisioning needs.
_fb_patches = lambda fn: patch('accounts.services.ensure_initialized')(  # noqa: E731
    patch('accounts.services.firebase_auth.create_user')(
        patch('accounts.services.firebase_auth.get_user_by_email')(fn)
    )
)


def make_coordinator(email='coord@club.test', club_name='Alpha FC'):
    """An approved (active) coordinator owning a fresh club."""
    user, club = register_coordinator(
        first_name='Coord', last_name='One', email=email,
        club_name=club_name, password=_PASSWORD,
    )
    user.is_active = True
    user.save(update_fields=['is_active'])
    return user, club


def make_player(club, email):
    user = User.objects.create(
        username=email, email=email, role=Roles.PLAYER,
        club=club, firebase_uid=f'uid-{email}',
    )
    profile = PlayerProfile.objects.create(
        user=user, date_of_birth=date(2011, 1, 1), eligibility=Eligibility.PENDING,
    )
    return user, profile


class CoordinatorSignupTests(TestCase):
    def test_signup_creates_club_and_pending_coordinator(self):
        resp = self.client.post(reverse('portal:signup'), {
            'first_name': 'Jane', 'last_name': 'Doe',
            'email': 'Jane@Club.Test',  # mixed case -> normalised
            'club_name': 'Cebu United',
            'password1': _PASSWORD, 'password2': _PASSWORD,
        })
        self.assertRedirects(resp, reverse('portal:signup-done'))

        club = Club.objects.get(name='Cebu United')
        user = User.objects.get(email='jane@club.test')
        self.assertEqual(user.role, Roles.COORDINATOR)
        self.assertEqual(user.club, club)
        self.assertFalse(user.is_active)          # pending superadmin approval
        self.assertTrue(user.has_usable_password())  # web session login
        self.assertIsNone(user.firebase_uid)      # no Firebase for web users

    def test_duplicate_email_rejected(self):
        make_coordinator(email='dupe@club.test', club_name='First FC')
        resp = self.client.post(reverse('portal:signup'), {
            'first_name': 'X', 'last_name': 'Y', 'email': 'dupe@club.test',
            'club_name': 'Second FC',
            'password1': _PASSWORD, 'password2': _PASSWORD,
        })
        self.assertEqual(resp.status_code, 200)  # re-rendered with an error
        self.assertEqual(User.objects.filter(email='dupe@club.test').count(), 1)
        self.assertFalse(Club.objects.filter(name='Second FC').exists())

    def test_password_mismatch_rejected(self):
        resp = self.client.post(reverse('portal:signup'), {
            'first_name': 'X', 'last_name': 'Y', 'email': 'mm@club.test',
            'club_name': 'MM FC',
            'password1': _PASSWORD, 'password2': 'different',
        })
        self.assertEqual(resp.status_code, 200)
        self.assertFalse(User.objects.filter(email='mm@club.test').exists())

    def test_pending_coordinator_cannot_login_until_approved(self):
        register_coordinator(
            first_name='P', last_name='Q', email='pending@club.test',
            club_name='Pending FC', password=_PASSWORD,
        )
        # Inactive -> ModelBackend refuses the login (OWASP A01).
        self.assertFalse(
            self.client.login(username='pending@club.test', password=_PASSWORD)
        )
        user = User.objects.get(email='pending@club.test')
        user.is_active = True
        user.save(update_fields=['is_active'])
        self.assertTrue(
            self.client.login(username='pending@club.test', password=_PASSWORD)
        )


class AccessControlTests(TestCase):
    def setUp(self):
        self.coord, self.club = make_coordinator()

    def test_anonymous_redirected_to_login(self):
        resp = self.client.get(reverse('portal:create-account'))
        self.assertEqual(resp.status_code, 302)
        self.assertIn('/portal/login/', resp['Location'])

    def test_staff_cannot_reach_create_account(self):
        staff, _ = provision_web_user(
            email='staff@club.test', first_name='S', last_name='T',
            role=Roles.SCHOOL_STAFF, club=self.club,
        )
        self.client.force_login(staff)
        self.assertEqual(
            self.client.get(reverse('portal:create-account')).status_code, 403
        )

    def test_coordinator_cannot_reach_staff_eligibility(self):
        self.client.force_login(self.coord)
        self.assertEqual(
            self.client.get(reverse('portal:staff-eligibility')).status_code, 403
        )

    def test_portal_pages_carry_csp_header(self):
        resp = self.client.get(reverse('portal:login'))
        self.assertIn('Content-Security-Policy', resp)


class CreateAccountTests(TestCase):
    def setUp(self):
        self.coord, self.club = make_coordinator()
        self.client.force_login(self.coord)

    @_fb_patches
    def test_create_player(self, mock_get, mock_create, _init):
        mock_get.side_effect = firebase_auth.UserNotFoundError('nf')
        mock_create.return_value = Mock(uid='player-uid')
        resp = self.client.post(reverse('portal:create-account'), {
            'account_type': 'player', 'first_name': 'Pat', 'last_name': 'Kick',
            'email': 'pat@club.test', 'date_of_birth': '2010-05-01',
            'middle_initial': 'X',
        })
        self.assertEqual(resp.status_code, 200)
        user = User.objects.get(email='pat@club.test')
        self.assertEqual(user.role, Roles.PLAYER)
        self.assertEqual(user.club, self.club)
        self.assertTrue(PlayerProfile.objects.filter(user=user).exists())
        self.assertContains(resp, 'Temporary password')

    @_fb_patches
    def test_create_coach(self, mock_get, mock_create, _init):
        mock_get.side_effect = firebase_auth.UserNotFoundError('nf')
        mock_create.return_value = Mock(uid='coach-uid')
        self.client.post(reverse('portal:create-account'), {
            'account_type': 'coach', 'first_name': 'Coa', 'last_name': 'Ch',
            'email': 'coach@club.test',
        })
        user = User.objects.get(email='coach@club.test')
        self.assertEqual(user.role, Roles.COACH)
        self.assertEqual(user.club, self.club)
        self.assertEqual(user.firebase_uid, 'coach-uid')

    def test_create_staff_is_web_user(self):
        self.client.post(reverse('portal:create-account'), {
            'account_type': 'staff', 'first_name': 'Sam', 'last_name': 'Staff',
            'email': 'sam@club.test',
        })
        user = User.objects.get(email='sam@club.test')
        self.assertEqual(user.role, Roles.SCHOOL_STAFF)
        self.assertEqual(user.club, self.club)
        self.assertTrue(user.is_active)
        self.assertTrue(user.has_usable_password())  # portal session login
        self.assertIsNone(user.firebase_uid)         # never touches Firebase

    @_fb_patches
    def test_create_guardian_links_to_club_player(self, mock_get, mock_create, _init):
        mock_get.side_effect = firebase_auth.UserNotFoundError('nf')
        mock_create.return_value = Mock(uid='guardian-uid')
        player, _ = make_player(self.club, 'linkme@club.test')
        self.client.post(reverse('portal:create-account'), {
            'account_type': 'guardian', 'first_name': 'Guar', 'last_name': 'Dian',
            'email': 'guardian@club.test', 'player': player.id,
        })
        guardian = User.objects.get(email='guardian@club.test')
        self.assertEqual(guardian.role, Roles.GUARDIAN)
        self.assertTrue(
            GuardianLink.objects.filter(guardian=guardian, player=player).exists()
        )

    def test_email_field_is_lowercased(self):
        self.client.post(reverse('portal:create-account'), {
            'account_type': 'staff', 'first_name': 'Up', 'last_name': 'Per',
            'email': 'MixedCase@Club.Test',
        })
        self.assertTrue(User.objects.filter(email='mixedcase@club.test').exists())


class ClubIsolationTests(TestCase):
    def test_players_page_shows_only_own_club(self):
        coord_a, club_a = make_coordinator(email='a@club.test', club_name='Club A')
        _coord_b, club_b = make_coordinator(email='b@club.test', club_name='Club B')
        make_player(club_a, 'in-a@club.test')
        make_player(club_b, 'in-b@club.test')

        self.client.force_login(coord_a)
        resp = self.client.get(reverse('portal:players'))
        self.assertContains(resp, 'in-a@club.test')
        self.assertNotContains(resp, 'in-b@club.test')


class StaffEligibilityTests(TestCase):
    def setUp(self):
        self.coord, self.club = make_coordinator()
        self.staff, _ = provision_web_user(
            email='staff@club.test', first_name='St', last_name='Aff',
            role=Roles.SCHOOL_STAFF, club=self.club,
        )
        self.player, self.profile = make_player(self.club, 'player@club.test')

    def test_staff_updates_eligibility_and_writes_history(self):
        self.client.force_login(self.staff)
        resp = self.client.post(reverse('portal:staff-eligibility'), {
            'player': self.profile.pk, 'eligibility': Eligibility.ELIGIBLE,
        })
        self.assertRedirects(resp, reverse('portal:staff-eligibility'))
        self.profile.refresh_from_db()
        self.assertEqual(self.profile.eligibility, Eligibility.ELIGIBLE)

        history = EligibilityHistory.objects.filter(player=self.player).latest(
            'changed_at'
        )
        self.assertEqual(history.new_status, Eligibility.ELIGIBLE)
        self.assertEqual(history.old_status, Eligibility.PENDING)
        self.assertEqual(history.changed_by, self.staff)  # attributed to staff

    def test_staff_cannot_set_eligibility_for_other_club_player(self):
        other_club = Club.objects.create(name='Other FC', slug='other-fc')
        _other_user, other_profile = make_player(other_club, 'other@club.test')

        self.client.force_login(self.staff)
        resp = self.client.post(reverse('portal:staff-eligibility'), {
            'player': other_profile.pk, 'eligibility': Eligibility.ELIGIBLE,
        })
        # The player is not in the club-scoped choices -> form rejects it.
        self.assertEqual(resp.status_code, 200)
        other_profile.refresh_from_db()
        self.assertEqual(other_profile.eligibility, Eligibility.PENDING)


class ApprovalActionTests(TestCase):
    def test_action_activates_only_pending_coordinators(self):
        user, _club = register_coordinator(
            first_name='P', last_name='Q', email='approve@club.test',
            club_name='Approve FC', password=_PASSWORD,
        )
        self.assertFalse(user.is_active)

        admin = CustomUserAdmin(User, site)
        with patch.object(CustomUserAdmin, 'message_user'):
            admin.approve_coordinators(Mock(), User.objects.filter(pk=user.pk))

        user.refresh_from_db()
        self.assertTrue(user.is_active)
