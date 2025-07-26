from django.shortcuts import render
from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.permissions import IsAuthenticatedOrReadOnly, IsAuthenticated
from rest_framework.response import Response
from marketplace.models import Listing
from marketplace.serializers import ListingReadSerializer, ListingWriteSerializer
from marketplace.permissions import IsOwnerOrReadOnly
from marketplace.pagination import CustomPageNumberPagination

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

    @action(detail=False, methods=['get'], permission_classes=[IsAuthenticated])
    def my_listings(self, request):
        """
        Get all listings created by the currently authenticated user.
        """
        listings = self.queryset.filter(seller=request.user)
        page = self.paginate_queryset(listings)
        if page is not None:
            serializer = self.get_serializer(page, many=True)
            return self.get_paginated_response(serializer.data)
        
        serializer = self.get_serializer(listings, many=True)
        return Response(serializer.data)