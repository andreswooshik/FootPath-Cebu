from django.contrib.auth import views as auth_views
from django.urls import path

from . import views

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
        ),
        name='login',
    ),
    path(
        'logout/',
        auth_views.LogoutView.as_view(next_page='portal:login'),
        name='logout',
    ),
    path('accounts/new/', views.create_account, name='create-account'),
    path('players/', views.players, name='players'),
    path('eligibility/', views.staff_eligibility, name='staff-eligibility'),
]
