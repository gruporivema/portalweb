from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import ProductViewSet, ProductBatchViewSet, FileUploadViewSet

router = DefaultRouter()
router.register(r'products', ProductViewSet, basename='product')
router.register(r'batches', ProductBatchViewSet, basename='batch')
router.register(r'uploads', FileUploadViewSet, basename='upload')

urlpatterns = [
    path('', include(router.urls)),
]
