from django.urls import path

from core_users.views import GoogleLoginView, UserProfileView

urlpatterns = [
    path('google/', GoogleLoginView.as_view(), name="google-auth"),
    path('profile/', UserProfileView.as_view(), name="profile"),
]