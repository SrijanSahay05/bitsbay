from rest_framework import permissions
import logging

logger = logging.getLogger(__name__)

class IsOwnerOrReadOnly(permissions.BasePermission):
    """
    Custom permission to only allow owners of a listing to delete it.
    """

    def has_permission(self, request, view):
        """Log permission checks at view level"""
        logger.info(f"=== PERMISSION CHECK (VIEW LEVEL) ===")
        logger.info(f"Method: {request.method}")
        logger.info(f"User: {request.user}")
        logger.info(f"Is authenticated: {request.user.is_authenticated}")
        logger.info(f"View action: {getattr(view, 'action', 'unknown')}")
        
        # Call parent permission check
        result = super().has_permission(request, view)
        logger.info(f"View level permission result: {result}")
        return result

    def has_object_permission(self, request, view, obj):
        """Log object-level permission checks"""
        logger.info(f"=== OBJECT PERMISSION CHECK ===")
        logger.info(f"Method: {request.method}")
        logger.info(f"User: {request.user}")
        logger.info(f"Object: {obj}")
        logger.info(f"Object seller: {obj.seller}")
        logger.info(f"Is safe method: {request.method in permissions.SAFE_METHODS}")
        logger.info(f"Is owner: {obj.seller == request.user}")
        
        # Read permissions are allowed to any request,
        # so we'll always allow GET, HEAD or OPTIONS requests.
        if request.method in permissions.SAFE_METHODS:
            logger.info(f"Allowing safe method: {request.method}")
            return True

        # Write permissions are only allowed to the owner of the listing.
        is_owner = obj.seller == request.user
        logger.info(f"Write permission result (is_owner): {is_owner}")
        return is_owner 