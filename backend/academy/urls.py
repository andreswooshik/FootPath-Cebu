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
    path('attendance/', views.AttendanceListView.as_view(), name='attendance-list'),
    path(
        'training-sessions/',
        views.TrainingSessionListCreateView.as_view(),
        name='training-sessions',
    ),
    path('devices/', views.DeviceRegisterView.as_view(), name='devices'),
    path(
        'admin/players/<int:player_id>/photo/',
        views.PlayerPhotoUploadView.as_view(),
        name='player-photo-upload',
    ),
]
