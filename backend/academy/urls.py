from django.urls import path

from . import views

urlpatterns = [
    path('players/', views.SquadListView.as_view(), name='players-list'),
    path('players/me/', views.MyProfileView.as_view(), name='players-me'),
    path('players/linked/', views.LinkedPlayersView.as_view(), name='players-linked'),
    path(
        'players/<int:player_id>/assessment/',
        views.PlayerAssessmentView.as_view(),
        name='player-assessment',
    ),
    path(
        'players/<int:player_id>/position/',
        views.PlayerPositionView.as_view(),
        name='player-position',
    ),
    path(
        'players/<int:player_id>/eligibility-history/',
        views.EligibilityHistoryView.as_view(),
        name='eligibility-history',
    ),
    path('age-tiers/', views.AgeTierSettingsView.as_view(), name='age-tiers'),
    path('attendance/', views.AttendanceListView.as_view(), name='attendance-list'),
    path(
        'attendance/session/<int:session_id>/',
        views.SessionAttendanceView.as_view(),
        name='attendance-session',
    ),
    path(
        'training-sessions/',
        views.TrainingSessionListCreateView.as_view(),
        name='training-sessions',
    ),
    path(
        'session-confirmations/',
        views.SessionConfirmationView.as_view(),
        name='session-confirmations',
    ),
    path('disputes/', views.DisputeListCreateView.as_view(), name='disputes'),
    path(
        'disputes/<int:pk>/',
        views.DisputeDetailView.as_view(),
        name='dispute-detail',
    ),
    path(
        'disputes/<int:pk>/responses/',
        views.DisputeResponseCreateView.as_view(),
        name='dispute-responses',
    ),
    path('injuries/', views.InjuryRecordListCreateView.as_view(), name='injuries'),
    path(
        'injuries/<int:pk>/',
        views.InjuryRecordDetailView.as_view(),
        name='injury-detail',
    ),
    path('devices/', views.DeviceRegisterView.as_view(), name='devices'),
    path(
        'admin/players/',
        views.AdminCreatePlayerView.as_view(),
        name='admin-player-create',
    ),
    path(
        'admin/players/<int:player_id>/photo/',
        views.PlayerPhotoUploadView.as_view(),
        name='player-photo-upload',
    ),
]
