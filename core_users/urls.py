from django.urls import path

from core_users.views import GoogleLoginView, UserProfileView, LogoutView
from rest_framework_simplejwt.views import TokenRefreshView

urlpatterns = [
    path('google/', GoogleLoginView.as_view(), name="google-auth"),
    path('logout/', LogoutView.as_view(), name="logout"),
    path('profile/', UserProfileView.as_view(), name="profile"),
    path('token/refresh/', TokenRefreshView.as_view(), name='token_refresh'),
]