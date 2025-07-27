from django.db import models
from core_users.models import CustomUser

class Listing(models.Model):
    """Model to represent a book listing on the platform"""

    seller = models.ForeignKey(
        CustomUser,
        on_delete=models.CASCADE,
        related_name='listings'
    )

    title = models.CharField(max_length=200)
    description = models.TextField()

    price = models.IntegerField(null=True, blank=True)

    #sorting tags
    tags = models.CharField(max_length=255, blank=True, help_text="Comma-seperated tags")
    negotiable = models.BooleanField(default=False)
    year = models.CharField(max_length=20, null=True, blank=True, help_text="e.g., 1st yr, 2nd yr, etc.")
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now = True)

    STATUS_CHOICES = [
        ("available", "Available"),
        ("sold", "Sold"),
    ]
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default="available")

    def __str__(self):
        return f"{self.title} by {self.seller.phone_number}"

    class Meta:
        ordering = ['-created_at']

