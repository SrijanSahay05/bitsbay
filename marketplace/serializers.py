from rest_framework import serializers
from marketplace.models import Listing


class ListingWriteSerializer(serializers.ModelSerializer):
    """
    Serializer for creating and updating Listing instances.
    Accepts a comma-separated string for tags
    """
    class Meta:
        model = Listing
        fields = ['title', 'description', 'price', 'tags', 'negotiable', 'year']


class ListingReadSerializer(serializers.ModelSerializer):
    """
    Serializer for reading/displaying Listing instances.
    Formats the output to match the desired structure.
    """
    id = serializers.CharField(source='pk', read_only=True)
    name = serializers.CharField(source='seller.get_full_name', read_only=True)
    phone = serializers.CharField(source='seller.phone_number', read_only=True)
    email = serializers.EmailField(source='seller.email', read_only=True)
    tags = serializers.SerializerMethodField()

    class Meta:
        model = Listing
        fields = [
            'id', 'name', 'title', 'description',
            'tags', 'negotiable', 'phone', 'email', 'year'
        ]

    def get_tags(self, obj):
        """
        Convert comma-separated string of tags into a list of strings.
        """
        if obj.tags:
            return [tag.strip() for tag in obj.tags.split(',')]
        return []