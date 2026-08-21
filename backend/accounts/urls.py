from django.urls import path

from . import views

urlpatterns = [
    path('auth/me/', views.MeView.as_view(), name='auth-me'),
    path('health/', views.health, name='health'),
    path('ready/', views.readiness, name='readiness'),
    path(
        'admin/users/',
        views.AdminUserListCreateView.as_view(),
        name='admin-users',
    ),
    path(
        'admin/clubs/',
        views.AdminClubListCreateView.as_view(),
        name='admin-clubs',
    ),
    path(
        'admin/clubs/<int:pk>/',
        views.AdminClubDetailView.as_view(),
        name='admin-club-detail',
    ),
    path(
        'admin/coordinators/',
        views.AdminCoordinatorCreateView.as_view(),
        name='admin-coordinators',
    ),
    path(
        'admin/users/<int:pk>/',
        views.AdminUserDetailView.as_view(),
        name='admin-user-detail',
    ),
    path(
        'admin/guardian-links/',
        views.AdminGuardianLinkListCreateView.as_view(),
        name='admin-guardian-links',
    ),
    path(
        'admin/guardian-links/<int:pk>/',
        views.AdminGuardianLinkDestroyView.as_view(),
        name='admin-guardian-link-detail',
    ),
]
