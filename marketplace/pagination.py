from rest_framework.pagination import PageNumberPagination
from rest_framework.response import Response
import math


class CustomPageNumberPagination(PageNumberPagination):
    """
    Custom pagination class that includes total pages count in the response.
    """
    page_size = 8
    page_size_query_param = 'page_size'
    max_page_size = 100

    def get_paginated_response(self, data):
        total_pages = math.ceil(self.page.paginator.count / self.page_size)
        
        # Create a flat response with total_pages and all listing data at the same level
        response_data = {
            'total_pages': total_pages
        }
        
        # Add each listing directly to the response
        for i, item in enumerate(data):
            response_data[f'item_{i}'] = item
            
        return Response(response_data) 