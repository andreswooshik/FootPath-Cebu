import re

from django.utils import timezone
from rest_framework import serializers


def normalize_mobile_number(value):
    number = re.sub(r'[\s()-]', '', value)
    if re.fullmatch(r'09\d{9}', number):
        number = '+63' + number[1:]
    elif re.fullmatch(r'639\d{9}', number):
        number = '+' + number
    if not re.fullmatch(r'\+639\d{9}', number):
        raise serializers.ValidationError('Enter a Philippine mobile number, e.g. 09171234567.')
    return number


class GuardianRegistrationSerializer(serializers.Serializer):
    firstName = serializers.CharField(max_length=150)
    lastName = serializers.CharField(max_length=150)
    email = serializers.EmailField(max_length=254)
    mobileNumber = serializers.CharField(max_length=30)

    def validate_email(self, value):
        return value.lower()

    def validate_mobileNumber(self, value):
        return normalize_mobile_number(value)


class PlayerRegistrationSerializer(serializers.Serializer):
    firstName = serializers.CharField(max_length=150)
    lastName = serializers.CharField(max_length=150)
    middleInitial = serializers.CharField(max_length=5, allow_blank=True, default='')
    email = serializers.EmailField(max_length=254, allow_blank=True, default='')
    dateOfBirth = serializers.DateField()

    def validate_email(self, value):
        return value.lower()

    def validate_dateOfBirth(self, value):
        if value > timezone.localdate():
            raise serializers.ValidationError('Date of birth cannot be in the future.')
        return value


class RegistrationCommandSerializer(serializers.Serializer):
    requestId = serializers.UUIDField()
    player = PlayerRegistrationSerializer()
    existingGuardianId = serializers.IntegerField(min_value=1, required=False)
    newGuardian = GuardianRegistrationSerializer(required=False)

    def validate(self, attrs):
        if ('existingGuardianId' in attrs) == ('newGuardian' in attrs):
            raise serializers.ValidationError('Select an existing guardian or enter a new guardian.')
        return attrs
