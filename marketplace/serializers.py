from rest_framework import serializers
from marketplace.models import Listing


class ListingWriteSerializer(serializers.ModelSerializer):
    """
    Serializer for creating and updating Listing instances.
    Accepts a comma-separated string for tags
    """
    class Meta:
        model = Listing
        fields = ['title', 'description', 'price', 'tags', 'negotiable', 'year', 'status']


class ListingReadSerializer(serializers.ModelSerializer):
    """
    Serializer for reading/displaying Listing instances.
    Formats the output to match the desired structure with organized tag display.
    """
    id = serializers.CharField(source='pk', read_only=True)
    name = serializers.CharField(source='seller.get_full_name', read_only=True)
    phone = serializers.CharField(source='seller.phone_number', read_only=True)
    email = serializers.EmailField(source='seller.email', read_only=True)
    tags = serializers.SerializerMethodField()
    display_tags = serializers.SerializerMethodField()

    class Meta:
        model = Listing
        fields = [
            'id', 'name', 'title', 'description',
            'tags','price', 'negotiable', 'phone', 'email', 'year', 'status'
        ]

    def get_tags(self, obj):
        """
        Convert comma-separated string of tags into a list of strings.
        """
        if obj.tags:
            return [tag.strip() for tag in obj.tags.split(',')]
        return []

    def get_display_tags(self, obj):
        """
        Organize tags into structured rows for consistent frontend display.
        Returns organized tag structure for UI layout.
        """
        # Row 1: Content/Category tags (custom tags from user)
        content_tags = []
        if obj.tags:
            content_tags = [tag.strip() for tag in obj.tags.split(',')]
        
        # Row 2: Status and Negotiable tags
        status_row = []
        status_row.append({
            'type': 'status',
            'value': obj.status.capitalize(),
            'color': 'green' if obj.status == 'available' else 'red'
        })
        
        if obj.negotiable:
            status_row.append({
                'type': 'negotiable',
                'value': 'Negotiable',
                'color': 'blue'
            })
        
        # Row 3: Year tag (if available)
        year_row = []
        if obj.year:
            year_row.append({
                'type': 'year',
                'value': obj.year,
                'color': 'purple'
            })
        
        # Row 4: Price tag (if available)
        price_row = []
        if obj.price is not None:
            price_row.append({
                'type': 'price',
                'value': f'₹{obj.price}',
                'color': 'orange'
            })
        
        return {
            'row_1_content': [{'type': 'content', 'value': tag, 'color': 'gray'} for tag in content_tags],
            'row_2_status': status_row,
            'row_3_year': year_row,
            'row_4_price': price_row
        }
