"""Strict fields for identifiers that must not be coerced from JSON numbers."""

from rest_framework import serializers


class StrictCharField(serializers.CharField):
    def to_internal_value(self, data):
        """Converts incoming strict char field data to validated internal values."""
        if not isinstance(data, str):
            self.fail('invalid')
        return super().to_internal_value(data)
