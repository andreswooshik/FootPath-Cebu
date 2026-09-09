"""Domain-focused API views extracted from the legacy view module."""

from ._view_support import *  # noqa: F401,F403

class DeviceRegisterView(APIView):
    """POST /api/devices/ {token, platform} — register/refresh an FCM token for
    the signed-in user. Idempotent (upsert by token)."""

    permission_classes = [IsAuthenticated]

    def post(self, request):
        token = (request.data.get('token') or '').strip()
        if not token:
            raise ValidationError('A device token is required.')
        DeviceToken.objects.update_or_create(
            token=token,
            defaults={
                'user': request.user,
                'platform': (request.data.get('platform') or '').strip(),
            },
        )
        return Response(status=status.HTTP_204_NO_CONTENT)

    def delete(self, request):
        """Forget this account's association with one device token."""
        token = (request.data.get('token') or '').strip()
        if not token:
            raise ValidationError('A device token is required.')
        DeviceToken.objects.filter(user=request.user, token=token).delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class NotificationListView(APIView):
    """GET the authenticated user's newest persistent inbox entries."""

    def get(self, request):
        records = NotificationRecord.objects.filter(user=request.user)[:100]
        return Response(NotificationRecordSerializer(records, many=True).data)


class NotificationUnreadCountView(APIView):
    def get(self, request):
        count = NotificationRecord.objects.filter(
            user=request.user, read_at__isnull=True,
        ).count()
        return Response({'count': count})


class NotificationReadView(APIView):
    def patch(self, request, pk):
        record = get_object_or_404(
            NotificationRecord, pk=pk, user=request.user,
        )
        if record.read_at is None:
            record.read_at = timezone.now()
            record.save(update_fields=['read_at'])
        return Response(NotificationRecordSerializer(record).data)


class NotificationReadAllView(APIView):
    def post(self, request):
        updated = NotificationRecord.objects.filter(
            user=request.user, read_at__isnull=True,
        ).update(read_at=timezone.now())
        return Response({'updated': updated})
