from django.urls import path
from . import views

app_name = 'Menu' 

urlpatterns = [
    path('', views.menu_view, name='home'),
]