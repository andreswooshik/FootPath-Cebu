"""Notification delivery and inbox models."""

from .model_players import *  # noqa: F401,F403

class DeviceToken(models.Model):
    """An FCM registration token for a user's device. Used to fan out push
    notifications (M3). A user may have several (multiple devices)."""

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='device_tokens',
    )
    token = models.CharField(max_length=255, unique=True)
    platform = models.CharField(max_length=20, blank=True)  # android / ios / web
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f'{self.user.email} · {self.platform or "?"}'


class NotificationRecord(models.Model):
    """Server-authoritative notification inbox entry for one recipient.

    FCM is only a best-effort delivery channel. Persisting the neutral message
    first gives users history even when permission is denied, a token is
    stale, or Firebase is temporarily unavailable.
    """

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='notification_records',
    )
    event_type = models.CharField(max_length=40)
    title = models.CharField(max_length=120)
    body = models.CharField(max_length=300)
    data = models.JSONField(default=dict, blank=True)
    read_at = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at', '-id']
        indexes = [
            models.Index(
                fields=['user', 'read_at', '-created_at'],
                name='notif_user_read_created_idx',
            ),
        ]

    def __str__(self):
        return f'{self.user.email} · {self.event_type} · {self.created_at:%Y-%m-%d}'
