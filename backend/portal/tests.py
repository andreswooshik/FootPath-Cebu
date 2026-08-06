"""Tests for the coordinator & school-staff web portal.

Covers signup + approval gating, session-auth role access control, club-scoped
account creation (players/coaches/staff/guardians), tenant isolation, and the
staff eligibility flow. Firebase is mocked wherever an app user (player / coach
/ guardian) is provisioned, so the suite runs offline like the rest.
"""
import tempfile
from datetime import date
from unittest.mock import Mock, patch

from django.contrib.admin.sites import site
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase, override_settings
from django.urls import reverse
from firebase_admin import auth as firebase_auth

from academy.models import (
    AuditLog, Eligibility, EligibilityHistory, PlayerPrivacyPin, PlayerProfile,
)
from accounts.admin import ClubAdmin, CustomUserAdmin
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


_MEDIA_ROOT = tempfile.mkdtemp()


def _license_file():
    """A fresh in-memory PDF upload (SimpleUploadedFile is single-read)."""
    return SimpleUploadedFile(
        'license.pdf', b'%PDF-1.4 test license', content_type='application/pdf'
    )


def _signup_data(**overrides):
    """Full valid club-registration POST payload; override individual fields."""
    data = {
        'club_name': 'Cebu United',
        'coordinator_name': 'Jane Doe',
        'head_coach_name': 'Coach Carter',
        'cvfa_membership': 'CVFA-12345',
        'email': 'jane@club.test',
        'password1': _PASSWORD,
        'password2': _PASSWORD,
        'coach_license': _license_file(),
    }
    data.update(overrides)
    return data


def make_coordinator(email='coord@club.test', club_name='Alpha FC',
                     is_school_affiliated=True):
    """An approved (active) coordinator owning a fresh club (school-affiliated
    by default so the staff / eligibility surfaces are available)."""
    user, club = register_coordinator(
        first_name='Coord', last_name='One', email=email,
        club_name=club_name, password=_PASSWORD,
        is_school_affiliated=is_school_affiliated,
        school_name='Demo School' if is_school_affiliated else '',
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


@override_settings(MEDIA_ROOT=_MEDIA_ROOT)
class CoordinatorSignupTests(TestCase):
    def test_signup_creates_club_and_pending_coordinator(self):
        resp = self.client.post(reverse('portal:signup'), _signup_data(
            coordinator_name='Jane Doe', email='Jane@Club.Test',  # normalised
            club_name='Cebu United',
        ))
        self.assertRedirects(resp, reverse('portal:signup-done'))

        club = Club.objects.get(name='Cebu United')
        user = User.objects.get(email='jane@club.test')
        self.assertEqual(user.role, Roles.COORDINATOR)
        self.assertEqual((user.first_name, user.last_name), ('Jane', 'Doe'))
        self.assertEqual(user.club, club)
        self.assertFalse(user.is_active)          # pending superadmin approval
        self.assertTrue(user.has_usable_password())  # web session login
        self.assertIsNone(user.firebase_uid)      # no Firebase for web users
        # Registration details are captured on the club.
        self.assertFalse(club.is_school_affiliated)   # checkbox left unticked
        self.assertEqual(club.head_coach_name, 'Coach Carter')
        self.assertEqual(club.cvfa_membership, 'CVFA-12345')
        self.assertTrue(club.coach_license.name.startswith('coach-licenses/'))

    def test_school_affiliated_signup_sets_flag(self):
        resp = self.client.post(reverse('portal:signup'), _signup_data(
            email='sa@club.test', club_name='Academy FC',
            is_school_affiliated='on', school_name='Cebu High',
        ))
        self.assertRedirects(resp, reverse('portal:signup-done'))
        club = Club.objects.get(name='Academy FC')
        self.assertTrue(club.is_school_affiliated)
        self.assertEqual(club.school_name, 'Cebu High')

    def test_affiliated_without_school_name_rejected(self):
        resp = self.client.post(reverse('portal:signup'), _signup_data(
            email='ns@club.test', club_name='NoName FC',
            is_school_affiliated='on',  # missing school_name
        ))
        self.assertEqual(resp.status_code, 200)
        self.assertFalse(Club.objects.filter(name='NoName FC').exists())

    def test_license_rejects_wrong_type(self):
        bad = SimpleUploadedFile('x.txt', b'nope', content_type='text/plain')
        resp = self.client.post(reverse('portal:signup'), _signup_data(
            email='bt@club.test', club_name='BadType FC', coach_license=bad,
        ))
        self.assertEqual(resp.status_code, 200)
        self.assertFalse(Club.objects.filter(name='BadType FC').exists())

    def test_license_rejects_oversize(self):
        # Validate at the form level so the size cap is asserted without
        # allocating a 50 MB payload — a POST round-trip would recompute size
        # from the real bytes and ignore an overridden .size.
        from .forms import COACH_LICENSE_MAX_BYTES, CoordinatorSignupForm
        big = SimpleUploadedFile('big.pdf', b'%PDF-1.4', content_type='application/pdf')
        big.size = COACH_LICENSE_MAX_BYTES + 1  # pretend it's over the cap
        form = CoordinatorSignupForm(
            data={
                'club_name': 'Big FC', 'coordinator_name': 'A B',
                'head_coach_name': 'HC', 'cvfa_membership': 'X-1',
                'email': 'big@club.test',
                'password1': _PASSWORD, 'password2': _PASSWORD,
            },
            files={'coach_license': big},
        )
        self.assertFalse(form.is_valid())
        self.assertIn('coach_license', form.errors)

    def test_duplicate_email_rejected(self):
        make_coordinator(email='dupe@club.test', club_name='First FC')
        resp = self.client.post(reverse('portal:signup'), _signup_data(
            email='dupe@club.test', club_name='Second FC',
        ))
        self.assertEqual(resp.status_code, 200)  # re-rendered with an error
        self.assertEqual(User.objects.filter(email='dupe@club.test').count(), 1)
        self.assertFalse(Club.objects.filter(name='Second FC').exists())

    def test_password_mismatch_rejected(self):
        resp = self.client.post(reverse('portal:signup'), _signup_data(
            email='mm@club.test', club_name='MM FC', password2='different',
        ))
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


@override_settings(MEDIA_ROOT=_MEDIA_ROOT, RATELIMIT_ENABLE=True)
class SignupHardeningTests(TestCase):
    """Abuse resistance on the public signup (audit finding S3)."""

    def setUp(self):
        from django.core.cache import cache
        cache.clear()  # isolate the per-IP counter from other tests

    def test_license_rejects_forged_signature(self):
        # Correct extension AND declared content-type, but the bytes are HTML —
        # exactly the polyglot the extension/content-type checks alone accept.
        forged = SimpleUploadedFile(
            'license.pdf', b'<html><script>alert(1)</script></html>',
            content_type='application/pdf',
        )
        resp = self.client.post(reverse('portal:signup'), _signup_data(
            email='forge@club.test', club_name='Forge FC', coach_license=forged,
        ))
        self.assertEqual(resp.status_code, 200)  # re-rendered with an error
        self.assertFalse(Club.objects.filter(name='Forge FC').exists())

    def test_signup_is_rate_limited_per_ip(self):
        # The limiter runs before the form, so even invalid POSTs are counted:
        # five are allowed through, the sixth is throttled with 429.
        for _ in range(5):
            self.assertEqual(
                self.client.post(reverse('portal:signup'), {}).status_code, 200
            )
        self.assertEqual(
            self.client.post(reverse('portal:signup'), {}).status_code, 429
        )


class SchoolStaffGatingTests(TestCase):
    """School staff exist only for school-affiliated clubs."""

    def test_non_affiliated_club_hides_staff_tab(self):
        coord, _club = make_coordinator(
            email='na@club.test', club_name='NoSchool FC',
            is_school_affiliated=False,
        )
        self.client.force_login(coord)
        resp = self.client.get(reverse('portal:create-account'))
        self.assertNotContains(resp, 'value="staff"')

    def test_non_affiliated_club_rejects_staff_post(self):
        coord, _club = make_coordinator(
            email='na2@club.test', club_name='NoSchool2 FC',
            is_school_affiliated=False,
        )
        self.client.force_login(coord)
        resp = self.client.post(reverse('portal:create-account'), {
            'account_type': 'staff', 'first_name': 'S', 'last_name': 'T',
            'email': 'blocked@club.test',
        })
        self.assertEqual(resp.status_code, 302)  # error redirect, not created
        self.assertFalse(User.objects.filter(email='blocked@club.test').exists())

    def test_service_refuses_staff_for_non_affiliated_club(self):
        from django.core.exceptions import PermissionDenied

        from .services import create_club_account
        _coord, club = make_coordinator(
            email='na3@club.test', club_name='NoSchool3 FC',
            is_school_affiliated=False,
        )
        with self.assertRaises(PermissionDenied):
            create_club_account(account_type='staff', club=club, data={
                'first_name': 'S', 'last_name': 'T', 'email': 'x@club.test',
            })

    def test_affiliated_club_shows_staff_tab(self):
        coord, _club = make_coordinator(
            email='aff@club.test', club_name='Aff FC', is_school_affiliated=True,
        )
        self.client.force_login(coord)
        resp = self.client.get(reverse('portal:create-account'))
        self.assertContains(resp, 'value="staff"')


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
        guardian = User.objects.create(
            username='parent@club.test', email='parent@club.test',
            role=Roles.GUARDIAN, club=self.club, firebase_uid='guardian-uid',
        )
        resp = self.client.post(reverse('portal:create-account'), {
            'account_type': 'player', 'first_name': 'Pat', 'last_name': 'Kick',
            'email': 'pat@club.test', 'date_of_birth': '2010-05-01',
            'middle_initial': 'X', 'guardian': guardian.id,
        })
        self.assertEqual(resp.status_code, 200)
        user = User.objects.get(email='pat@club.test')
        self.assertEqual(user.role, Roles.PLAYER)
        self.assertEqual(user.club, self.club)
        self.assertTrue(
            GuardianLink.objects.filter(guardian=guardian, player=user).exists()
        )
        self.assertTrue(PlayerProfile.objects.filter(user=user).exists())
        self.assertContains(resp, 'Temporary password')

    def test_create_player_requires_an_active_guardian(self):
        response = self.client.post(reverse('portal:create-account'), {
            'account_type': 'player', 'first_name': 'No', 'last_name': 'Parent',
            'email': 'no-parent@club.test', 'date_of_birth': '2010-05-01',
        })
        self.assertEqual(response.status_code, 200)
        self.assertFalse(User.objects.filter(email='no-parent@club.test').exists())

    def test_coordinator_can_reset_player_privacy_pin(self):
        player, _ = make_player(self.club, 'pin-player@club.test')
        PlayerPrivacyPin.objects.create(
            player=player, pin_hash='argon2$placeholder', failed_attempts=3,
        )
        response = self.client.post(
            reverse('portal:player-pin-reset', args=[player.id])
        )
        self.assertRedirects(response, reverse('portal:players'))
        state = PlayerPrivacyPin.objects.get(player=player)
        self.assertEqual(state.pin_hash, '')
        self.assertEqual(state.failed_attempts, 0)
        self.assertTrue(AuditLog.objects.filter(
            action='player_pin.reset', actor=self.coord, target=player.email,
        ).exists())

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

    def test_staff_sees_club_history_but_not_other_clubs(self):
        """The page's Status History section is the staff-facing history view
        (spec: view eligibility status history of linked players), scoped to
        the staff member's club like everything else."""
        self.profile.eligibility = Eligibility.ACADEMIC_WARNING
        self.profile._changed_by = self.staff
        self.profile.save(update_fields=['eligibility'])

        other_club = Club.objects.create(name='Hist FC', slug='hist-fc')
        _u, other_profile = make_player(other_club, 'hist@club.test')
        other_profile.eligibility = Eligibility.NOT_ELIGIBLE
        other_profile.save(update_fields=['eligibility'])

        self.client.force_login(self.staff)
        resp = self.client.get(reverse('portal:staff-eligibility'))
        self.assertContains(resp, 'Status History')
        self.assertContains(resp, 'Academic Warning')
        self.assertNotContains(resp, 'hist@club.test')

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


class GuardianLinkManagementTests(TestCase):
    """Coordinators add/remove guardian↔player links after creation."""

    def setUp(self):
        self.coord, self.club = make_coordinator()
        self.guardian = User.objects.create(
            username='g@club.test', email='g@club.test',
            role=Roles.GUARDIAN, club=self.club, firebase_uid='uid-g',
        )
        self.player, _ = make_player(self.club, 'linkme@club.test')
        self.client.force_login(self.coord)

    def test_coordinator_links_and_unlinks(self):
        resp = self.client.post(reverse('portal:guardians'), {
            'guardian': self.guardian.pk, 'player': self.player.pk,
        })
        self.assertRedirects(resp, reverse('portal:guardians'))
        link = GuardianLink.objects.get(
            guardian=self.guardian, player=self.player
        )

        resp = self.client.post(
            reverse('portal:guardian-unlink', args=[link.pk])
        )
        self.assertRedirects(resp, reverse('portal:guardians'))
        self.assertFalse(GuardianLink.objects.filter(pk=link.pk).exists())

    def test_cross_club_accounts_are_not_offered(self):
        other_club = Club.objects.create(name='X FC', slug='x-fc')
        outsider, _ = make_player(other_club, 'outsider@club.test')
        resp = self.client.post(reverse('portal:guardians'), {
            'guardian': self.guardian.pk, 'player': outsider.pk,
        })
        # Not in the club-scoped choices -> form error, no link.
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(GuardianLink.objects.count(), 0)

    def test_cannot_unlink_another_clubs_link(self):
        other_club = Club.objects.create(name='Y FC', slug='y-fc')
        other_guardian = User.objects.create(
            username='og@club.test', email='og@club.test',
            role=Roles.GUARDIAN, club=other_club, firebase_uid='uid-og',
        )
        other_player, _ = make_player(other_club, 'op@club.test')
        link = GuardianLink.objects.create(
            guardian=other_guardian, player=other_player
        )
        resp = self.client.post(
            reverse('portal:guardian-unlink', args=[link.pk])
        )
        self.assertEqual(resp.status_code, 403)
        self.assertTrue(GuardianLink.objects.filter(pk=link.pk).exists())


class PlayerPhotoUploadTests(TestCase):
    def setUp(self):
        self.coord, self.club = make_coordinator()
        self.player, self.profile = make_player(self.club, 'photo@club.test')
        self.client.force_login(self.coord)

    def _photo(self, name='p.jpg', content_type='image/jpeg', size=100):
        return SimpleUploadedFile(name, b'x' * size, content_type=content_type)

    @patch('portal.views.upload_photo', return_value='player-photos/1.jpg')
    def test_coordinator_uploads_a_photo(self, mock_upload):
        resp = self.client.post(
            reverse('portal:player-photo', args=[self.player.pk]),
            {'photo': self._photo()},
        )
        self.assertRedirects(resp, reverse('portal:players'))
        mock_upload.assert_called_once()
        self.profile.refresh_from_db()
        self.assertEqual(self.profile.photo_path, 'player-photos/1.jpg')

    @patch('portal.views.upload_photo')
    def test_non_image_is_rejected(self, mock_upload):
        resp = self.client.post(
            reverse('portal:player-photo', args=[self.player.pk]),
            {'photo': self._photo('x.pdf', content_type='application/pdf')},
        )
        self.assertRedirects(resp, reverse('portal:players'))
        mock_upload.assert_not_called()

    @patch('portal.views.upload_photo')
    def test_other_clubs_player_is_404(self, mock_upload):
        other_club = Club.objects.create(name='Z FC', slug='z-fc')
        outsider, _ = make_player(other_club, 'zp@club.test')
        resp = self.client.post(
            reverse('portal:player-photo', args=[outsider.pk]),
            {'photo': self._photo()},
        )
        self.assertEqual(resp.status_code, 404)
        mock_upload.assert_not_called()


class PasswordChangeTests(TestCase):
    """Portal users (session auth) can rotate their own password — School
    Staff otherwise keep their relayed one-time password forever."""

    def test_staff_changes_their_password(self):
        _coord, club = make_coordinator()
        staff, old_password = provision_web_user(
            email='rotate@club.test', first_name='Ro', last_name='Tate',
            role=Roles.SCHOOL_STAFF, club=club,
        )
        self.client.force_login(staff)
        resp = self.client.post(reverse('portal:password-change'), {
            'old_password': old_password,
            'new_password1': 'N3w-Portal-Pass!',
            'new_password2': 'N3w-Portal-Pass!',
        })
        self.assertRedirects(resp, reverse('portal:dashboard'))
        staff.refresh_from_db()
        self.assertTrue(staff.check_password('N3w-Portal-Pass!'))

    def test_anonymous_is_redirected_to_login(self):
        resp = self.client.get(reverse('portal:password-change'))
        self.assertEqual(resp.status_code, 302)
        self.assertIn(reverse('portal:login'), resp['Location'])


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

    def test_club_registration_actions_approve_and_disapprove(self):
        user, club = register_coordinator(
            first_name='C', last_name='A', email='club-action@club.test',
            club_name='Club Action FC', password=_PASSWORD,
        )
        admin = ClubAdmin(Club, site)

        club.is_active = False
        club.save(update_fields=['is_active'])
        with patch.object(ClubAdmin, 'message_user'):
            admin.approve_registrations(Mock(), Club.objects.filter(pk=club.pk))

        user.refresh_from_db()
        club.refresh_from_db()
        self.assertTrue(user.is_active)
        self.assertTrue(club.is_active)

        with patch.object(ClubAdmin, 'message_user'):
            admin.disapprove_registrations(Mock(), Club.objects.filter(pk=club.pk))

        user.refresh_from_db()
        club.refresh_from_db()
        self.assertFalse(user.is_active)
        self.assertFalse(club.is_active)
