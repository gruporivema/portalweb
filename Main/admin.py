from django.contrib import admin
from .models import FileUpload, ProductBatch, Product


@admin.register(FileUpload)
class FileUploadAdmin(admin.ModelAdmin):
    list_display = ['id', 'file_type', 'uploaded_by', 'uploaded_at', 'status', 'total_records', 'processed_records']
    list_filter = ['file_type', 'status', 'uploaded_at']
    search_fields = ['uploaded_by__username']
    readonly_fields = ['uploaded_at']
    ordering = ['-uploaded_at']


@admin.register(ProductBatch)
class ProductBatchAdmin(admin.ModelAdmin):
    list_display = ['id', 'batch_code', 'file_upload', 'created_at', 'synced_to_protheus', 'synced_at']
    list_filter = ['synced_to_protheus', 'created_at']
    search_fields = ['batch_code']
    readonly_fields = ['created_at']
    ordering = ['-created_at']


@admin.register(Product)
class ProductAdmin(admin.ModelAdmin):
    list_display = ['product_code', 'description', 'product_type', 'sale_price', 'current_stock', 'synced_to_protheus', 'created_at']
    list_filter = ['synced_to_protheus', 'active', 'product_type', 'product_group', 'created_at']
    search_fields = ['product_code', 'description', 'barcode', 'supplier_name']
    readonly_fields = ['created_at', 'updated_at']
    ordering = ['-created_at']

    fieldsets = (
        ('Informações Básicas', {
            'fields': ('batch', 'product_code', 'description', 'short_description')
        }),
        ('Classificação', {
            'fields': ('product_type', 'product_group', 'product_category')
        }),
        ('Unidades e Medidas', {
            'fields': ('unit_of_measure', 'second_unit', 'conversion_factor', 'weight', 'weight_unit')
        }),
        ('Precificação', {
            'fields': ('sale_price', 'cost_price', 'currency')
        }),
        ('Estoque', {
            'fields': ('current_stock', 'minimum_stock', 'warehouse_code')
        }),
        ('Informações Fiscais', {
            'fields': ('ncm_code', 'ipi_percentage', 'icms_percentage')
        }),
        ('Fornecedor', {
            'fields': ('supplier_code', 'supplier_name')
        }),
        ('Outros', {
            'fields': ('barcode', 'active', 'observations')
        }),
        ('Sincronização Protheus', {
            'fields': ('synced_to_protheus', 'protheus_sync_date', 'protheus_error')
        }),
        ('Controle', {
            'fields': ('created_at', 'updated_at', 'raw_data')
        }),
    )
