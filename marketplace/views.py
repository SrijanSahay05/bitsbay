from django.shortcuts import render
from rest_framework import viewsets
from rest_framework.permissions import IsAuthenticatedOrReadOnly
from marketplace.models import Listing
from marketplace.serializers import ListingReadSerializer, ListingWriteSerializer
from marketplace.permissions import IsOwnerOrReadOnly

class ListingViewSet(viewsets.ModelViewSet):
    """
    This viewset provides `list`, `create`, `retrieve`, `update`,
    and `destroy` actions for Listing. It uses different serializers
    for reading and writing data.
    """
    # Use select_related to optimize the query by fetching the seller
    # in the same database query as the listing.
    queryset = Listing.objects.select_related('seller').all()
    permission_classes = [IsAuthenticatedOrReadOnly, IsOwnerOrReadOnly]

    def get_serializer_class(self):
        """
        Return the appropriate serializer class based on the request method.
        """
        if self.action in ['create', 'update', 'partial_update']:
            return ListingWriteSerializer
        return ListingReadSerializer

    def perform_create(self, serializer):
        """
        Set the seller of the listing to the currently authenticated user.
        """
        serializer.save(seller=self.request.user)