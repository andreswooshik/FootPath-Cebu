from unittest.mock import patch

from django.contrib.admin.sites import AdminSite
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from .admin import ClubAdmin, CustomUserAdmin
from .models import Club, Roles, User


class ActiveCheckboxAdminTests(TestCase):
    def test_user_change_form_hides_raw_active_checkbox(self):
        field_names = {
            field
            for _title, options in CustomUserAdmin.fieldsets
            for field in options['fields']
        }
        self.assertNotIn('is_active', field_names)

    def test_club_form_hides_raw_active_checkbox(self):
        model_admin = ClubAdmin(Club, AdminSite())
        self.assertIn('is_active', model_admin.get_exclude(None, None))


class CoachProfilePhotoTests(APITestCase):
    def setUp(self):
        self.club = Club.objects.create(name='Coach Photo Club', slug='coach-photo')
        self.coach = User.objects.create_user(
            username='coach-photo@example.test',
            email='coach-photo@example.test',
            role=Roles.COACH,
            club=self.club,
        )
        self.player = User.objects.create_user(
            username='player-photo@example.test',
            email='player-photo@example.test',
            role=Roles.PLAYER,
            club=self.club,
        )

    @staticmethod
    def _photo():
        return SimpleUploadedFile(
            'coach.jpg',
            b'\xff\xd8\xffcoach-photo',
            content_type='image/jpeg',
        )

    @patch(
        'accounts.serializers.signed_photo_url',
        return_value='https://signed.example/coach.jpg',
    )
    @patch(
        'accounts.views.upload_photo',
        return_value='player-photos/1.jpg',
    )
    def test_coach_uploads_own_private_profile_photo(self, upload, signed_url):
        self.client.force_authenticate(self.coach)

        response = self.client.post(
            reverse('auth-me-photo'),
            {'photo': self._photo()},
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.coach.refresh_from_db()
        self.assertEqual(self.coach.profile_photo_path, 'player-photos/1.jpg')
        self.assertEqual(
            response.data['photo_url'],
            'https://signed.example/coach.jpg',
        )
        upload.assert_called_once()
        signed_url.assert_called_once_with('player-photos/1.jpg')

    @patch('accounts.views.upload_photo')
    def test_non_coach_is_rejected_before_storage(self, upload):
        self.client.force_authenticate(self.player)

        response = self.client.post(
            reverse('auth-me-photo'),
            {'photo': self._photo()},
            format='multipart',
        )

        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        upload.assert_not_called()
