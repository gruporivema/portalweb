from rest_framework import serializers
from Main.models import Product, ProductBatch, FileUpload


class ProductSerializer(serializers.ModelSerializer):
    batch_code = serializers.CharField(source='batch.batch_code', read_only=True)

    class Meta:
        model = Product
        fields = [
            'id',
            'batch_code',
            'product_code',
            'description',
            'short_description',
            'product_type',
            'product_group',
            'product_category',
            'unit_of_measure',
            'second_unit',
            'conversion_factor',
            'sale_price',
            'cost_price',
            'currency',
            'current_stock',
            'minimum_stock',
            'warehouse_code',
            'ncm_code',
            'ipi_percentage',
            'icms_percentage',
            'supplier_code',
            'supplier_name',
            'barcode',
            'weight',
            'weight_unit',
            'active',
            'observations',
            'synced_to_protheus',
            'protheus_sync_date',
            'created_at',
            'updated_at',
        ]
        read_only_fields = ['id', 'created_at', 'updated_at', 'batch_code']


class ProductSyncSerializer(serializers.Serializer):
    product_ids = serializers.ListField(
        child=serializers.IntegerField(),
        required=False,
        help_text='Lista de IDs de produtos para sincronizar. Se vazio, sincroniza todos pendentes.'
    )
    batch_code = serializers.CharField(
        required=False,
        help_text='Código do lote para sincronizar todos os produtos do lote.'
    )


class ProductSyncUpdateSerializer(serializers.Serializer):
    product_id = serializers.IntegerField(required=True)
    success = serializers.BooleanField(required=True)
    error_message = serializers.CharField(required=False, allow_blank=True, allow_null=True)


class ProductBatchSerializer(serializers.ModelSerializer):
    total_products = serializers.SerializerMethodField()
    synced_products = serializers.SerializerMethodField()
    file_upload_info = serializers.SerializerMethodField()

    class Meta:
        model = ProductBatch
        fields = [
            'id',
            'batch_code',
            'created_at',
            'synced_to_protheus',
            'synced_at',
            'total_products',
            'synced_products',
            'file_upload_info',
        ]
        read_only_fields = ['id', 'batch_code', 'created_at']

    def get_total_products(self, obj):
        return obj.products.count()

    def get_synced_products(self, obj):
        return obj.products.filter(synced_to_protheus=True).count()

    def get_file_upload_info(self, obj):
        if obj.file_upload:
            return {
                'id': obj.file_upload.id,
                'file_type': obj.file_upload.file_type,
                'uploaded_at': obj.file_upload.uploaded_at,
                'uploaded_by': obj.file_upload.uploaded_by.username if obj.file_upload.uploaded_by else None,
            }
        return None


class FileUploadSerializer(serializers.ModelSerializer):
    uploaded_by_username = serializers.CharField(source='uploaded_by.username', read_only=True)
    batch_code = serializers.CharField(source='batch.batch_code', read_only=True)

    class Meta:
        model = FileUpload
        fields = [
            'id',
            'file',
            'file_type',
            'uploaded_by_username',
            'uploaded_at',
            'status',
            'total_records',
            'processed_records',
            'error_message',
            'batch_code',
        ]
        read_only_fields = ['id', 'uploaded_at', 'uploaded_by_username', 'batch_code']
