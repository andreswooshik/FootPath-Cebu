from django.urls import path

from . import views

urlpatterns = [
    path('auth/me/', views.MeView.as_view(), name='auth-me'),
    path('health/', views.health, name='health'),
]
