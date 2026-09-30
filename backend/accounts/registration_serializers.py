import re

from django.utils import timezone
from rest_framework import serializers


def normalize_mobile_number(value):
    """Normalizes a registration mobile number and rejects unsupported formats."""
    number = re.sub(r'[\s()-]', '', value)
    if re.fullmatch(r'09\d{9}', number):
        number = '+63' + number[1:]
    elif re.fullmatch(r'639\d{9}', number):
        number = '+' + number
    if not re.fullmatch(r'\+639\d{9}', number):
        raise serializers.ValidationError('Enter a Philippine mobile number, e.g. 09171234567.')
    return number


def normalize_middle_initial(value):
    """Normalizes a middle initial and rejects invalid values."""
    initial = value.strip().rstrip('.').upper()
    if not initial:
        return ''
    if not re.fullmatch(r'[A-Z]', initial):
        raise serializers.ValidationError('Enter one letter for the middle initial.')
    return initial


class GuardianRegistrationSerializer(serializers.Serializer):
    firstName = serializers.CharField(max_length=150)
    middleInitial = serializers.CharField(
        max_length=2, required=False, allow_blank=True, default=''
    )
    lastName = serializers.CharField(max_length=150)
    email = serializers.EmailField(max_length=254)
    mobileNumber = serializers.CharField(max_length=30)

    def validate_email(self, value):
        """Checks and normalizes email for guardian registration."""
        return value.lower()

    def validate_middleInitial(self, value):
        """Checks and normalizes middle initial for guardian registration."""
        return normalize_middle_initial(value)

    def validate_mobileNumber(self, value):
        """Checks and normalizes mobile number for guardian registration."""
        return normalize_mobile_number(value)


class PlayerRegistrationSerializer(serializers.Serializer):
    firstName = serializers.CharField(max_length=150)
    lastName = serializers.CharField(max_length=150)
    middleInitial = serializers.CharField(max_length=5, allow_blank=True, default='')
    dateOfBirth = serializers.DateField()

    def to_internal_value(self, data):
        """Converts incoming player registration data to validated internal values."""
        if 'email' in data:
            raise serializers.ValidationError(
                {'email': 'Player profiles do not have a separate login email.'}
            )
        return super().to_internal_value(data)

    def validate_dateOfBirth(self, value):
        """Checks and normalizes date of birth for player registration."""
        if value > timezone.localdate():
            raise serializers.ValidationError('Date of birth cannot be in the future.')
        return value

    def validate_middleInitial(self, value):
        """Checks and normalizes middle initial for player registration."""
        return normalize_middle_initial(value)


class RegistrationCommandSerializer(serializers.Serializer):
    requestId = serializers.UUIDField()
    player = PlayerRegistrationSerializer()
    existingGuardianId = serializers.IntegerField(min_value=1, required=False)
    newGuardian = GuardianRegistrationSerializer(required=False)

    def validate(self, attrs):
        """Validates the combined request fields for registration command."""
        if ('existingGuardianId' in attrs) == ('newGuardian' in attrs):
            raise serializers.ValidationError(
                'Select an existing guardian or enter a new guardian.'
            )
        return attrs


class MemberRegistrationSerializer(serializers.Serializer):
    requestId = serializers.UUIDField()
    role = serializers.ChoiceField(choices=['GUARDIAN', 'COACH'])
    firstName = serializers.CharField(max_length=150)
    middleInitial = serializers.CharField(
        max_length=2, required=False, allow_blank=True, default=''
    )
    lastName = serializers.CharField(max_length=150)
    email = serializers.EmailField(max_length=254)
    mobileNumber = serializers.CharField(max_length=30)

    def validate_middleInitial(self, value):
        """Checks and normalizes middle initial for member registration."""
        return normalize_middle_initial(value)

    def validate_email(self, value):
        """Checks and normalizes email for member registration."""
        return value.strip().lower()

    def validate_mobileNumber(self, value):
        """Checks and normalizes mobile number for member registration."""
        return normalize_mobile_number(value)
