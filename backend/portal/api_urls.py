from django.urls import path

from .api_views import MobileClubRegistrationView

urlpatterns = [
    path(
        'club-registrations/',
        MobileClubRegistrationView.as_view(),
        name='mobile-club-registration',
    ),
]
