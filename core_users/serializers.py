from rest_framework import serializers
from core_users.models import CustomUser

import re


class UserProfileSerializer(serializers.ModelSerializer):
    """Serializer for user profile"""

    class Meta:
        model = CustomUser
        fields = ['id', 'email', 'first_name', 'last_name', 'phone_number']
        read_only_fields = ['id', 'email', 'first_name', 'last_name']

    def validate_phone_number(self, value):
        """ Check that the phone number is 10 digits."""
        if value and not value.isdigit():
            raise serializers.ValidationError("Phone number must contain only digits")
        if value and len(value) != 10:
            raise serializers.ValidationError("Phone number must be exactly 10 digits long")
        return value
