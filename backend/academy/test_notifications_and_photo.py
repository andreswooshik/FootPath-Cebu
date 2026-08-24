import os
from unittest.mock import patch

from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase

from accounts.models import Club, Roles, User

from .models import DeviceToken, NotificationRecord, PlayerProfile
from .notifications import _send_to_users
from .storage import (
    MAX_PHOTO_BYTES,
    signed_photo_url,
    upload_photo,
    validate_photo_upload,
)


class StoragePhotoValidationTests(TestCase):
    def _photo(self, size):
        upload = SimpleUploadedFile(
            'player.jpg', b'\xff\xd8\xffphoto', content_type='image/jpeg',
        )
        upload.size = size
        return upload

    def test_photo_size_limit_is_25_mb(self):
        self.assertEqual(MAX_PHOTO_BYTES, 25 * 1024 * 1024)
        self.assertEqual(
            validate_photo_upload(self._photo(MAX_PHOTO_BYTES)),
            'image/jpeg',
        )
        with self.assertRaisesMessage(ValueError, '25 MB or smaller'):
            validate_photo_upload(self._photo(MAX_PHOTO_BYTES + 1))


class StorageAuthenticationHeaderTests(TestCase):
    def _storage_env(self, key):
        return patch.dict(os.environ, {
            'SUPABASE_URL': 'https://project.supabase.co',
            'SUPABASE_SERVICE_KEY': key,
            'SUPABASE_PHOTO_BUCKET': 'player-photos',
        })

    def test_upload_uses_supported_headers_for_current_and_legacy_keys(self):
        cases = (
            ('sb_secret_current', False),
            ('legacy.header.signature', True),
        )
        for key, expects_bearer in cases:
            with self.subTest(key=key), self._storage_env(key), patch(
                'academy.storage.httpx.post'
            ) as post:
                post.return_value.raise_for_status.return_value = None

                result = upload_photo(
                    42, b'image-bytes', content_type='image/jpeg',
                )

                self.assertEqual(result, 'player-photos/42.jpg')
                headers = post.call_args.kwargs['headers']
                self.assertEqual(headers['apikey'], key)
                self.assertEqual(headers['Content-Type'], 'image/jpeg')
                self.assertEqual(headers['x-upsert'], 'true')
                if expects_bearer:
                    self.assertEqual(headers['Authorization'], f'Bearer {key}')
                else:
                    self.assertNotIn('Authorization', headers)

    def test_signed_url_uses_supported_headers_for_current_and_legacy_keys(self):
        cases = (
            ('sb_secret_current', False),
            ('legacy.header.signature', True),
        )
        for index, (key, expects_bearer) in enumerate(cases):
            photo_path = f'player-photos/auth-header-test-{index}.jpg'
            cache_key = f'photo-signed-url:3600:{photo_path}'
            cache.delete(cache_key)
            self.addCleanup(cache.delete, cache_key)
            with self.subTest(key=key), self._storage_env(key), patch(
                'academy.storage.httpx.post'
            ) as post:
                post.return_value.raise_for_status.return_value = None
                post.return_value.json.return_value = {
                    'signedURL': f'/object/sign/{photo_path}?token=test',
                }

                result = signed_photo_url(photo_path)

                self.assertEqual(
                    result,
                    'https://project.supabase.co/storage/v1'
                    f'/object/sign/{photo_path}?token=test',
                )
                headers = post.call_args.kwargs['headers']
                self.assertEqual(headers['apikey'], key)
                if expects_bearer:
                    self.assertEqual(headers['Authorization'], f'Bearer {key}')
                else:
                    self.assertNotIn('Authorization', headers)

    def test_upload_rejects_a_publishable_key_as_server_credentials(self):
        with self._storage_env('sb_publishable_wrong-key'):
            with self.assertRaisesMessage(
                RuntimeError, 'SUPABASE_SERVICE_KEY must be an sb_secret_ key',
            ):
                upload_photo(42, b'image-bytes', content_type='image/jpeg')


class NotificationInboxTests(APITestCase):
    def setUp(self):
        self.club = Club.objects.create(
            name='Inbox Club', slug='inbox-club', is_active=True,
        )
        self.user = User.objects.create_user(
            username='player-inbox@example.test',
            email='player-inbox@example.test',
            role=Roles.PLAYER,
            club=self.club,
        )
        self.other = User.objects.create_user(
            username='other-inbox@example.test',
            email='other-inbox@example.test',
            role=Roles.GUARDIAN,
            club=self.club,
        )
        self.own = NotificationRecord.objects.create(
            user=self.user,
            event_type='session_updated',
            title='Schedule updated',
            body='Sign in to view it.',
            data={'sessionId': '12'},
        )
        self.other_record = NotificationRecord.objects.create(
            user=self.other,
            event_type='assessment_saved',
            title='Assessment updated',
            body='Sign in to view it.',
        )
        self.client.force_authenticate(self.user)

    def test_list_and_unread_count_are_current_user_only(self):
        response = self.client.get(reverse('notifications'))
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertEqual([row['id'] for row in response.data], [self.own.id])
        count = self.client.get(reverse('notification-unread-count'))
        self.assertEqual(count.data, {'count': 1})

    def test_mark_read_cannot_touch_another_users_record(self):
        denied = self.client.patch(
            reverse('notification-read', args=[self.other_record.pk]), {},
            format='json',
        )
        self.assertEqual(denied.status_code, status.HTTP_404_NOT_FOUND)
        ok = self.client.patch(
            reverse('notification-read', args=[self.own.pk]), {}, format='json',
        )
        self.assertEqual(ok.status_code, status.HTTP_200_OK)
        self.assertTrue(ok.data['isRead'])

    def test_mark_all_read_is_scoped_to_current_user(self):
        response = self.client.post(reverse('notification-read-all'), {})
        self.assertEqual(response.data, {'updated': 1})
        self.own.refresh_from_db()
        self.other_record.refresh_from_db()
        self.assertIsNotNone(self.own.read_at)
        self.assertIsNone(self.other_record.read_at)

    @patch('academy.notifications.ensure_initialized')
    def test_inbox_persists_when_firebase_is_unavailable(self, initialize):
        initialize.side_effect = RuntimeError('not configured')
        sent = _send_to_users(
            {self.user.pk},
            title='Eligibility updated',
            body='Academic eligibility status was updated. Sign in to view it.',
            data={'type': 'eligibility_changed', 'playerId': str(self.user.pk)},
        )
        self.assertEqual(sent, 0)
        record = NotificationRecord.objects.filter(
            user=self.user, event_type='eligibility_changed',
        ).latest('id')
        self.assertNotIn('eligibility', record.data)
        self.assertNotIn('previous', record.data)


class DeviceLifecycleTests(APITestCase):
    def setUp(self):
        club = Club.objects.create(
            name='Device Club', slug='device-club', is_active=True,
        )
        self.user = User.objects.create_user(
            username='device@example.test', email='device@example.test',
            role=Roles.COACH, club=club,
        )
        self.other = User.objects.create_user(
            username='other-device@example.test',
            email='other-device@example.test',
            role=Roles.COACH, club=club,
        )
        self.client.force_authenticate(self.user)

    def test_register_refresh_and_account_scoped_unregister(self):
        url = reverse('devices')
        response = self.client.post(
            url, {'token': 'mine', 'platform': 'android'}, format='json',
        )
        self.assertEqual(response.status_code, status.HTTP_204_NO_CONTENT)
        DeviceToken.objects.create(user=self.other, token='theirs')
        self.client.delete(url, {'token': 'theirs'}, format='json')
        self.assertTrue(DeviceToken.objects.filter(token='theirs').exists())
        self.client.delete(url, {'token': 'mine'}, format='json')
        self.assertFalse(DeviceToken.objects.filter(token='mine').exists())


class MobilePlayerPhotoTests(APITestCase):
    def setUp(self):
        self.club = Club.objects.create(
            name='Photo Club', slug='photo-club', is_active=True,
        )
        self.other_club = Club.objects.create(
            name='Other Photo Club', slug='other-photo-club', is_active=True,
        )
        self.coach = User.objects.create_user(
            username='photo-coach@example.test',
            email='photo-coach@example.test',
            role=Roles.COACH,
            club=self.club,
        )
        self.player = User.objects.create_user(
            username='photo-player@example.test',
            email='photo-player@example.test',
            role=Roles.PLAYER,
            club=self.club,
        )
        self.profile = PlayerProfile.objects.create(user=self.player)
        self.outsider = User.objects.create_user(
            username='photo-outsider@example.test',
            email='photo-outsider@example.test',
            role=Roles.PLAYER,
            club=self.other_club,
        )
        PlayerProfile.objects.create(user=self.outsider)
        self.client.force_authenticate(self.coach)

    def _photo(self):
        return SimpleUploadedFile(
            'player.jpg', b'\xff\xd8\xff' + b'photo', content_type='image/jpeg',
        )

    @patch('academy.views.upload_photo', return_value='player-photos/player.jpg')
    def test_same_club_coach_uploads_from_mobile_endpoint(self, upload):
        response = self.client.post(
            reverse('player-photo-upload-mobile', args=[self.player.pk]),
            {'photo': self._photo()},
            format='multipart',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.profile.refresh_from_db()
        self.assertEqual(self.profile.photo_path, 'player-photos/player.jpg')
        upload.assert_called_once()

    @patch('academy.views.upload_photo')
    def test_cross_club_coach_is_rejected_before_storage(self, upload):
        response = self.client.post(
            reverse('player-photo-upload-mobile', args=[self.outsider.pk]),
            {'photo': self._photo()},
            format='multipart',
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        upload.assert_not_called()

    @patch(
        'academy.views.upload_photo',
        return_value='player-photos/player.jpg',
    )
    def test_player_can_replace_their_own_roster_photo(self, upload):
        self.client.force_authenticate(self.player)
        response = self.client.post(
            reverse('player-photo-upload-mobile', args=[self.player.pk]),
            {'photo': self._photo()},
            format='multipart',
        )
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.profile.refresh_from_db()
        self.assertEqual(self.profile.photo_path, 'player-photos/player.jpg')
        upload.assert_called_once()

    @patch('academy.views.upload_photo')
    def test_player_cannot_replace_another_players_photo(self, upload):
        self.client.force_authenticate(self.outsider)
        response = self.client.post(
            reverse('player-photo-upload-mobile', args=[self.player.pk]),
            {'photo': self._photo()},
            format='multipart',
        )
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        upload.assert_not_called()
