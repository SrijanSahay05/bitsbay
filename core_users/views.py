from django.conf import settings
from django.contrib.auth import get_user_model
from rest_framework.permissions import IsAuthenticated

from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework_simplejwt.tokens import RefreshToken

from google.oauth2 import id_token
from google.auth.transport import requests

from core_users.serializers import UserProfileSerializer
# Get the custom User model
User = get_user_model()


class GoogleLoginView(APIView):
    """
    Handles Google authentication using only an ID token.
    """

    def post(self, request):
        """
        Validates a Google ID token and performs user sign-in or sign-up.

        Expects:
            {
                "id_token": "your_google_id_token_here"
            }

        Returns on Success:
            {
                "refresh": "your_refresh_token",
                "access": "your_access_token",
                "has_phone_number": true/false
            }

        Returns on Failure:
            {
                "error": "A descriptive error message"
            }
        """
        try:
            # Get the ID token from the request data
            token = request.data.get('id_token')
            if not token:
                return Response(
                    {"error": "ID token is required"},
                    status=status.HTTP_400_BAD_REQUEST
                )

            # Validate the ID token with Google
            try:
                # The 'requests.Request()' object is used to perform the validation request.
                # The audience is your Google OAuth2 Client ID to ensure the token was issued for your app.
                id_info = id_token.verify_oauth2_token(
                    token, requests.Request(), settings.GOOGLE_OAUTH2_CLIENT_ID
                )
            except ValueError as e:
                # This exception is raised if the token is invalid for any reason
                # (e.g., expired, wrong audience, malformed).
                return Response(
                    {"error": f"Invalid ID token: {str(e)}"},
                    status=status.HTTP_401_UNAUTHORIZED
                )

            # Extract user information from the validated token
            email = id_info.get("email")
            first_name = id_info.get("given_name", "")
            last_name = id_info.get("family_name", "")

            if not email:
                return Response(
                    {"error": "Email not found in token"},
                    status=status.HTTP_400_BAD_REQUEST
                )

            # Get or create the user in your database
            # The user is identified by their email. If they don't exist, a new user is created
            # with a random, unusable password.
            user, created = User.objects.get_or_create(
                email=email,
                defaults={
                    'first_name': first_name,
                    'last_name': last_name,
                    # 'password': "test@123"
                }
            )

            if created:
                user.set_unusable_password()
                user.save()

            # Generate JWT tokens for the user
            refresh = RefreshToken.for_user(user)

            # Return the required tokens and the phone number status
            return Response({
                'refresh': str(refresh),
                'access': str(refresh.access_token),
                'has_phone_number': hasattr(user, 'phone_number') and bool(user.phone_number)
            })

        except Exception as e:
            # A general catch-all for any unexpected errors during the process.
            return Response(
                {"error": f"An unexpected error occurred: {str(e)}"},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR
            )

class UserProfileView(APIView):
    """View to manager the user profile's information. Requires access token to be sent."""

    permission_classes = [IsAuthenticated]
    serializer_class = UserProfileSerializer

    def get(self, request):
        """Retrieve profile of the authenticated user"""
        user = request.user
        serializer = self.serializer_class(user)
        return  Response(serializer.data, status=status.HTTP_200_OK)

    def put(self, request):
        """Update profile for the authenticated user (only phone number update is permitted)"""
        user = request.user
        serializer = self.serializer_class(user, data=request.data, partial=True)

        if serializer.is_valid():
            # Ensure only the phone number can be updated via this endpoint
            if 'phone_number' in serializer.validated_data:
                user.phone_number = serializer.validated_data['phone_number']
                user.save(update_fields=['phone_number'])
                return Response(self.serializer_class(user).data, status=status.HTTP_200_OK)
            else:
                return Response(
                    {"error": "Only the phone_number field can be updated."},
                    status=status.HTTP_400_BAD_REQUEST
                )
        return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

