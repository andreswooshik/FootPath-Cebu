from django.contrib.auth import views as auth_views
from django.urls import path

from . import views
from .forms import PortalAuthenticationForm

app_name = 'portal'

urlpatterns = [
    path('', views.dashboard, name='dashboard'),
    path('signup/', views.signup, name='signup'),
    path('signup/done/', views.signup_done, name='signup-done'),
    path(
        'login/',
        auth_views.LoginView.as_view(
            template_name='portal/login.html',
            redirect_authenticated_user=True,
            authentication_form=PortalAuthenticationForm,
        ),
        name='login',
    ),
    path(
        'logout/',
        auth_views.LogoutView.as_view(next_page='portal:login'),
        name='logout',
    ),
    path(
        'password/',
        views.PortalPasswordChangeView.as_view(),
        name='password-change',
    ),
    path(
        'mobile-access/',
        views.coordinator_mobile_access,
        name='mobile-access',
    ),
    path('accounts/new/', views.create_account, name='create-account'),
    path('players/', views.players, name='players'),
    path(
        'players/<int:player_id>/pin/reset/',
        views.player_pin_reset,
        name='player-pin-reset',
    ),
    path('coaches/', views.coaches, name='coaches'),
    path('guardians/', views.guardians, name='guardians'),
    path('tournaments/', views.tournament_schedules, name='tournaments'),
    path(
        'tournaments/<int:schedule_id>/',
        views.tournament_schedule_detail,
        name='tournament-detail',
    ),
    path(
        'tournaments/<int:schedule_id>/delete/',
        views.tournament_schedule_delete,
        name='tournament-delete',
    ),
    path(
        'fixtures/<int:fixture_id>/edit/',
        views.tournament_fixture_edit,
        name='tournament-fixture-edit',
    ),
    path(
        'fixtures/<int:fixture_id>/delete/',
        views.tournament_fixture_delete,
        name='tournament-fixture-delete',
    ),
    path(
        'guardians/links/<int:pk>/remove/',
        views.guardian_unlink,
        name='guardian-unlink',
    ),
    path(
        'players/<int:player_id>/photo/',
        views.player_photo,
        name='player-photo',
    ),
    path('eligibility/', views.staff_eligibility, name='staff-eligibility'),
    path('disputes/', views.staff_disputes, name='staff-disputes'),
    path(
        'disputes/<int:pk>/',
        views.staff_dispute_detail,
        name='staff-dispute-detail',
    ),
]
