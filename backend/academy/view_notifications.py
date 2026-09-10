"""Domain-focused API views extracted from the legacy view module."""

from django.shortcuts import get_object_or_404
from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from academy.model_notifications import (
    DeviceToken,
    NotificationRecord,
)
from academy.serializer_workflows import NotificationRecordSerializer

from .serializer_notifications import DeviceTokenRequestSerializer


class DeviceRegisterView(APIView):
    """POST /api/devices/ {token, platform} — register/refresh an FCM token for
    the signed-in user. Idempotent (upsert by token)."""

    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = DeviceTokenRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        token = serializer.validated_data['token']
        DeviceToken.objects.update_or_create(
            token=token,
            defaults={
                'user': request.user,
                'platform': serializer.validated_data['platform'],
            },
        )
        return Response(status=status.HTTP_204_NO_CONTENT)

    def delete(self, request):
        """Forget this account's association with one device token."""
        serializer = DeviceTokenRequestSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        token = serializer.validated_data['token']
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
            user=request.user,
            read_at__isnull=True,
        ).count()
        return Response({'count': count})


class NotificationReadView(APIView):
    def patch(self, request, pk):
        record = get_object_or_404(
            NotificationRecord,
            pk=pk,
            user=request.user,
        )
        if record.read_at is None:
            record.read_at = timezone.now()
            record.save(update_fields=['read_at'])
        return Response(NotificationRecordSerializer(record).data)


class NotificationReadAllView(APIView):
    def post(self, request):
        updated = NotificationRecord.objects.filter(
            user=request.user,
            read_at__isnull=True,
        ).update(read_at=timezone.now())
        return Response({'updated': updated})
