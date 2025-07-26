from django.contrib import admin
from .models import Listing

@admin.register(Listing)
class ListingAdmin(admin.ModelAdmin):
    list_display = ('title', 'seller', 'year', 'price', 'negotiable', 'created_at')
    list_filter = ('negotiable', 'year', 'created_at')
    search_fields = ('title', 'description', 'seller__email')
    readonly_fields = ('created_at', 'updated_at')
    fieldsets = (
        (None, {
            'fields': ('seller', 'title', 'description', 'price')
        }),
        ('Details', {
            'fields': ('tags', 'negotiable', 'year')
        }),
        ('Timestamps', {
            'fields': ('created_at', 'updated_at'),
            'classes': ('collapse',)
        }),
    )
