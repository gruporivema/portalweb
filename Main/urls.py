from django.urls import path
from Main import views

app_name = 'Main'

urlpatterns = [
    # Authentication
    path('login/', views.login_view, name='login'),
    path('logout/', views.logout_view, name='logout'),

    # File upload and processing
    path('upload/', views.upload_file, name='upload_file'),
    path('uploads/', views.upload_history, name='upload_history'),

    # Products
    path('products/', views.product_list, name='product_list'),
    path('products/<int:pk>/', views.product_detail, name='product_detail'),

    # Purchase order validation workflow
    path('filter/<str:batch_code>/', views.filter_selection, name='filter_selection'),
    path('validation/<str:batch_code>/', views.validation_table, name='validation_table'),
    path('validate-codes/', views.validate_codes, name='validate_codes'),
    path('reprocess/<str:batch_code>/', views.reprocess_batch, name='reprocess_batch'),
    path('submit/<str:batch_code>/', views.submit_to_protheus, name='submit_to_protheus'),
]
