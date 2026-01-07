from django.apps import AppConfig


class MenuConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'Menu'
        
    def ready(self):
        try:
            from . import templatetags
        except ImportError:
            pass