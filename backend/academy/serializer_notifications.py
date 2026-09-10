"""Validated device registration requests."""

from rest_framework import serializers

from accounts.fields import StrictCharField


class DeviceTokenRequestSerializer(serializers.Serializer):
    token = StrictCharField(max_length=255)
    platform = serializers.ChoiceField(
        choices=('', 'android', 'ios', 'web'),
        required=False,
        default='',
    )
