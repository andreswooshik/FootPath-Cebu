"""Traceable regression tests for the adviser-approved 24 hierarchy rules."""
from datetime import date
from unittest.mock import patch

from django.core.exceptions import PermissionDenied
from django.urls import reverse
from rest_framework.test import APITestCase

from academy.models import Eligibility, EligibilityHistory, PlayerProfile
from academy.serializers import PlayerSerializer
from portal.services import (
    create_club_account,
    link_guardian,
    set_player_eligibility,
)

from .models import Club, ClubTypes, GuardianLink, Roles, User
from .services import provision_club_coordinator, provision_web_user


class ApprovedClubHierarchyTests(APITestCase):
    """Each method number maps to the corresponding adviser security test."""

    def setUp(self):
        self.firebase_patcher = patch(
            'accounts.services.link_or_create_firebase_user',
            side_effect=self._fake_firebase_link,
        )
        self.firebase_patcher.start()
        self.addCleanup(self.firebase_patcher.stop)

        self.super_admin = User.objects.create(
            username='super@footpath.test', email='super@footpath.test',
            role=Roles.ADMIN, is_staff=True, is_superuser=True,
        )
        self.school = Club.objects.create(
            name='School FC', slug='school-fc', is_school_affiliated=True,
            school_name='FootPath School',
        )
        self.independent = Club.objects.create(
            name='Independent FC', slug='independent-fc',
            is_school_affiliated=False,
        )
        self.other = Club.objects.create(name='Other FC', slug='other-fc')
        self.school_coordinator, _ = provision_club_coordinator(
            email='school.coord@footpath.test', first_name='School',
            last_name='Coordinator', club=self.school, password='SafePass123!',
        )
        self.independent_coordinator, _ = provision_club_coordinator(
            email='independent.coord@footpath.test', first_name='Independent',
            last_name='Coordinator', club=self.independent,
            password='SafePass123!',
        )
        self.other_coordinator, _ = provision_club_coordinator(
            email='other.coord@footpath.test', first_name='Other',
            last_name='Coordinator', club=self.other, password='SafePass123!',
        )

    @staticmethod
    def _fake_firebase_link(user, *, password=None):
        user.firebase_uid = f'uid-{user.username}'
        user.set_unusable_password()
        return password or 'TempPass123!'

    @staticmethod
    def _member(*, email, role, club):
        return User.objects.create(
            username=email, email=email, role=role, club=club,
            firebase_uid=f'uid-{email}',
        )

    @staticmethod
    def _profile(*, email, club):
        user = ApprovedClubHierarchyTests._member(
            email=email, role=Roles.PLAYER, club=club,
        )
        return user, PlayerProfile.objects.create(
            user=user, date_of_birth=date(2012, 1, 1),
        )

    def _portal_post(self, coordinator, payload):
        self.client.force_login(coordinator)
        return self.client.post(reverse('portal:create-account'), payload)

    def _player_payload(self, *, email, guardian=None, **extra):
        payload = {
            'account_type': 'player', 'email': email,
            'first_name': 'Player', 'last_name': 'Test',
            'middle_initial': 'Q', 'date_of_birth': '2012-01-01',
        }
        if guardian is not None:
            payload['guardian'] = guardian.id
        payload.update(extra)
        return payload

    def test_01_super_admin_can_create_club(self):
        self.client.force_authenticate(self.super_admin)
        response = self.client.post(reverse('admin-clubs'), {
            'name': 'Created FC', 'club_type': ClubTypes.INDEPENDENT,
            'is_active': True,
        }, format='json')
        self.assertEqual(response.status_code, 201)
        self.assertTrue(Club.objects.filter(name='Created FC').exists())

    def test_02_super_admin_can_choose_school_club(self):
        self.client.force_authenticate(self.super_admin)
        response = self.client.post(reverse('admin-clubs'), {
            'name': 'New School FC', 'club_type': ClubTypes.SCHOOL,
            'school_name': 'New School', 'is_active': True,
        }, format='json')
        self.assertEqual(response.status_code, 201)
        club = Club.objects.get(name='New School FC')
        self.assertTrue(club.is_school_affiliated)
        self.assertEqual(club.club_type, ClubTypes.SCHOOL)

    def test_03_super_admin_can_choose_independent_club(self):
        self.client.force_authenticate(self.super_admin)
        response = self.client.post(reverse('admin-clubs'), {
            'name': 'New Independent FC',
            'club_type': ClubTypes.INDEPENDENT, 'is_active': True,
        }, format='json')
        self.assertEqual(response.status_code, 201)
        club = Club.objects.get(name='New Independent FC')
        self.assertFalse(club.is_school_affiliated)
        self.assertEqual(club.club_type, ClubTypes.INDEPENDENT)

    def test_04_super_admin_creates_coordinator_for_selected_valid_club(self):
        club = Club.objects.create(name='Selected FC', slug='selected-fc')
        self.client.force_authenticate(self.super_admin)
        response = self.client.post(reverse('admin-coordinators'), {
            'email': 'selected.coord@footpath.test', 'first_name': 'Selected',
            'last_name': 'Coordinator', 'club_id': club.id,
            'password': 'SafePass123!', 'is_active': True,
        }, format='json')
        self.assertEqual(response.status_code, 201)
        coordinator = User.objects.get(email='selected.coord@footpath.test')
        self.assertEqual(coordinator.role, Roles.COORDINATOR)
        self.assertEqual(coordinator.club, club)
        invalid = self.client.post(reverse('admin-coordinators'), {
            'email': 'invalid.coord@footpath.test', 'first_name': 'Invalid',
            'last_name': 'Club', 'club_id': 999999,
        }, format='json')
        self.assertEqual(invalid.status_code, 400)

    def test_05_coordinator_can_create_player_in_own_club(self):
        response = self._portal_post(
            self.school_coordinator,
            self._player_payload(email='player05@footpath.test'),
        )
        self.assertEqual(response.status_code, 200)
        self.assertTrue(User.objects.filter(
            email='player05@footpath.test', role=Roles.PLAYER,
            club=self.school,
        ).exists())

    def test_06_player_automatically_receives_coordinator_club(self):
        self._portal_post(
            self.school_coordinator,
            self._player_payload(email='player06@footpath.test'),
        )
        self.assertEqual(
            User.objects.get(email='player06@footpath.test').club,
            self.school,
        )

    def test_07_coordinator_cannot_create_player_in_another_club(self):
        other_guardian = self._member(
            email='other.guardian07@footpath.test', role=Roles.GUARDIAN,
            club=self.other,
        )
        response = self._portal_post(
            self.school_coordinator,
            self._player_payload(
                email='player07@footpath.test', guardian=other_guardian,
                club_id=self.other.id,
            ),
        )
        self.assertEqual(response.status_code, 200)
        self.assertFalse(User.objects.filter(email='player07@footpath.test').exists())

    def test_08_modified_club_id_cannot_bypass_server_derived_club(self):
        guardian = self._member(
            email='guardian08@footpath.test', role=Roles.GUARDIAN,
            club=self.school,
        )
        self._portal_post(
            self.school_coordinator,
            self._player_payload(
                email='player08@footpath.test', guardian=guardian,
                club_id=self.other.id,
            ),
        )
        player = User.objects.get(email='player08@footpath.test')
        self.assertEqual(player.club, self.school)
        self.assertNotEqual(player.club, self.other)

    def test_09_created_player_always_has_exactly_one_profile(self):
        self._portal_post(
            self.school_coordinator,
            self._player_payload(email='player09@footpath.test'),
        )
        player = User.objects.get(email='player09@footpath.test')
        self.assertEqual(PlayerProfile.objects.filter(user=player).count(), 1)

    def test_10_coordinator_can_create_coach_in_own_club(self):
        response = self._portal_post(self.school_coordinator, {
            'account_type': 'coach', 'email': 'coach10@footpath.test',
            'first_name': 'Coach', 'last_name': 'Ten',
        })
        self.assertEqual(response.status_code, 200)
        self.assertTrue(User.objects.filter(
            email='coach10@footpath.test', role=Roles.COACH, club=self.school,
        ).exists())

    def test_11_coordinator_can_create_guardian_in_own_club(self):
        response = self._portal_post(self.school_coordinator, {
            'account_type': 'guardian', 'email': 'guardian11@footpath.test',
            'first_name': 'Guardian', 'last_name': 'Eleven',
        })
        self.assertEqual(response.status_code, 200)
        self.assertTrue(User.objects.filter(
            email='guardian11@footpath.test', role=Roles.GUARDIAN,
            club=self.school,
        ).exists())

    def test_12_coordinator_can_link_guardian_to_same_club_player(self):
        guardian = self._member(
            email='guardian12@footpath.test', role=Roles.GUARDIAN,
            club=self.school,
        )
        player, _ = self._profile(email='player12@footpath.test', club=self.school)
        self.client.force_login(self.school_coordinator)
        response = self.client.post(reverse('portal:guardians'), {
            'guardian': guardian.id, 'player': player.id,
        })
        self.assertEqual(response.status_code, 302)
        self.assertTrue(GuardianLink.objects.filter(
            guardian=guardian, player=player,
        ).exists())

    def test_13_cross_club_guardian_link_is_rejected(self):
        guardian = self._member(
            email='guardian13@footpath.test', role=Roles.GUARDIAN,
            club=self.school,
        )
        player, _ = self._profile(email='player13@footpath.test', club=self.other)
        with self.assertRaises(PermissionDenied):
            link_guardian(
                coordinator=self.school_coordinator,
                guardian=guardian,
                player=player,
            )
        self.assertFalse(GuardianLink.objects.filter(
            guardian=guardian, player=player,
        ).exists())

    def test_14_school_club_coordinator_can_create_school_staff(self):
        response = self._portal_post(self.school_coordinator, {
            'account_type': 'staff', 'email': 'staff14@footpath.test',
            'first_name': 'Staff', 'last_name': 'Fourteen',
        })
        self.assertEqual(response.status_code, 200)
        self.assertTrue(User.objects.filter(
            email='staff14@footpath.test', role=Roles.SCHOOL_STAFF,
            club=self.school,
        ).exists())

    def test_15_independent_club_coordinator_cannot_create_school_staff(self):
        response = self._portal_post(self.independent_coordinator, {
            'account_type': 'staff', 'email': 'staff15@footpath.test',
            'first_name': 'Blocked', 'last_name': 'Staff',
        })
        self.assertEqual(response.status_code, 302)
        self.assertFalse(User.objects.filter(email='staff15@footpath.test').exists())
        with self.assertRaises(PermissionDenied):
            create_club_account(
                account_type='staff', coordinator=self.independent_coordinator,
                data={
                    'email': 'service15@footpath.test', 'first_name': 'Blocked',
                    'last_name': 'Service',
                },
            )

    def test_16_school_club_can_use_status_only_eligibility_module(self):
        staff, _ = provision_web_user(
            email='staff16@footpath.test', first_name='School', last_name='Staff',
            role=Roles.SCHOOL_STAFF, club=self.school,
        )
        _player, profile = self._profile(
            email='player16@footpath.test', club=self.school,
        )
        set_player_eligibility(
            staff=staff, player_profile=profile,
            new_status=Eligibility.ELIGIBLE,
        )
        profile.refresh_from_db()
        self.assertEqual(profile.eligibility, Eligibility.ELIGIBLE)
        self.assertTrue(EligibilityHistory.objects.filter(player=profile.user).exists())

    def test_17_independent_club_gets_not_applicable_eligibility_behavior(self):
        player, profile = self._profile(
            email='player17@footpath.test', club=self.independent,
        )
        self.assertFalse(
            PlayerSerializer(profile).data['academicEligibilityApplicable']
        )
        self.client.force_authenticate(player)
        response = self.client.get(reverse('eligibility-history', args=[player.id]))
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.data, {'applicable': False, 'results': []})

    def test_18_neither_club_type_stores_raw_grades(self):
        field_names = {field.name.lower() for field in PlayerProfile._meta.fields}
        history_fields = {field.name.lower() for field in EligibilityHistory._meta.fields}
        forbidden = {
            'gpa', 'grade', 'grades', 'subject_grade', 'report_card',
            'transcript', 'grade_upload',
        }
        self.assertTrue(field_names.isdisjoint(forbidden))
        self.assertTrue(history_fields.isdisjoint(forbidden))
        _player, profile = self._profile(
            email='privacy18@footpath.test', club=self.school,
        )
        response_keys = {key.lower() for key in PlayerSerializer(profile).data}
        self.assertTrue(response_keys.isdisjoint(forbidden))
        self.assertEqual(set(Eligibility.values), {
            'ELIGIBLE', 'NOT_ELIGIBLE', 'PENDING', 'ACADEMIC_WARNING',
        })

    def _assert_role_cannot_create_accounts(self, role, email):
        user = self._member(email=email, role=role, club=self.school)
        if role == Roles.PLAYER:
            PlayerProfile.objects.create(
                user=user, date_of_birth=date(2012, 1, 1)
            )
        self.client.force_login(user)
        response = self.client.post(reverse('portal:create-account'), {
            'account_type': 'coach', 'email': f'created-by-{email}',
            'first_name': 'Not', 'last_name': 'Allowed',
        })
        self.assertEqual(response.status_code, 403)
        self.assertFalse(User.objects.filter(email=f'created-by-{email}').exists())

    def test_19_coach_cannot_create_accounts(self):
        self._assert_role_cannot_create_accounts(Roles.COACH, 'coach19@test.test')

    def test_20_player_cannot_create_accounts(self):
        self._assert_role_cannot_create_accounts(Roles.PLAYER, 'player20@test.test')

    def test_21_guardian_cannot_create_accounts(self):
        self._assert_role_cannot_create_accounts(
            Roles.GUARDIAN, 'guardian21@test.test'
        )

    def test_22_school_staff_cannot_create_accounts(self):
        self._assert_role_cannot_create_accounts(
            Roles.SCHOOL_STAFF, 'staff22@test.test'
        )

    def test_23_normal_coordinator_cannot_create_another_coordinator(self):
        before = User.objects.filter(role=Roles.COORDINATOR).count()
        response = self._portal_post(self.school_coordinator, {
            'account_type': 'coordinator',
            'email': 'coordinator23@footpath.test',
            'first_name': 'No', 'last_name': 'Coordinator',
        })
        self.assertEqual(response.status_code, 302)
        self.assertEqual(User.objects.filter(role=Roles.COORDINATOR).count(), before)

    def test_24_coordinator_cannot_manage_super_admin_club_operations(self):
        self.client.force_authenticate(self.school_coordinator)
        response = self.client.post(reverse('admin-clubs'), {
            'name': 'Unauthorized FC', 'club_type': ClubTypes.INDEPENDENT,
        }, format='json')
        self.assertEqual(response.status_code, 403)
        self.assertFalse(Club.objects.filter(name='Unauthorized FC').exists())
