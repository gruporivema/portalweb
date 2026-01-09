from django.db import models
from django.contrib.auth.models import User
from django.utils import timezone


class FileUpload(models.Model):
    FILE_TYPE_CHOICES = [
        ('EXCEL', 'Excel'),
        ('XML', 'XML'),
    ]

    STATUS_CHOICES = [
        ('PENDING', 'Pendente'),
        ('PROCESSING', 'Processando'),
        ('COMPLETED', 'Concluído'),
        ('FAILED', 'Falhou'),
    ]

    file = models.FileField(upload_to='uploads/%Y/%m/%d/')
    file_type = models.CharField(max_length=10, choices=FILE_TYPE_CHOICES)
    uploaded_by = models.ForeignKey(User, on_delete=models.SET_NULL, null=True, blank=True)
    uploaded_at = models.DateTimeField(default=timezone.now)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='PENDING')
    total_records = models.IntegerField(default=0)
    processed_records = models.IntegerField(default=0)
    error_message = models.TextField(null=True, blank=True)

    class Meta:
        ordering = ['-uploaded_at']
        verbose_name = 'Upload de Arquivo'
        verbose_name_plural = 'Uploads de Arquivos'

    def __str__(self):
        return f"{self.file_type} - {self.uploaded_at.strftime('%d/%m/%Y %H:%M')}"


class ProductBatch(models.Model):
    file_upload = models.OneToOneField(FileUpload, on_delete=models.CASCADE, related_name='batch')
    created_at = models.DateTimeField(default=timezone.now)
    batch_code = models.CharField(max_length=50, unique=True)

    # Fornecedor code provided by user (OPTIONAL - remove blank=True, null=True to make REQUIRED)
    fornecedor_code = models.CharField(max_length=50, null=True, blank=True, verbose_name='Código do Fornecedor')

    # Product group code provided by user for normalization
    product_group = models.CharField(max_length=50, null=True, blank=True, verbose_name='Grupo de Produtos')

    synced_to_protheus = models.BooleanField(default=False)
    synced_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-created_at']
        verbose_name = 'Lote de Produtos'
        verbose_name_plural = 'Lotes de Produtos'

    def __str__(self):
        return f"Lote {self.batch_code}"


class Product(models.Model):
    batch = models.ForeignKey(ProductBatch, on_delete=models.CASCADE, related_name='products')

    # Basic product information
    product_code = models.CharField(max_length=50, db_index=True, verbose_name='Código do Produto')
    description = models.CharField(max_length=255, verbose_name='Descrição')
    short_description = models.CharField(max_length=100, null=True, blank=True, verbose_name='Descrição Curta')

    # Product classification
    product_type = models.CharField(max_length=50, null=True, blank=True, verbose_name='Tipo de Produto')
    product_group = models.CharField(max_length=50, null=True, blank=True, verbose_name='Grupo')
    product_category = models.CharField(max_length=50, null=True, blank=True, verbose_name='Categoria')

    # Unit and measurement
    unit_of_measure = models.CharField(max_length=10, null=True, blank=True, verbose_name='Unidade de Medida')
    second_unit = models.CharField(max_length=10, null=True, blank=True, verbose_name='Segunda Unidade')
    conversion_factor = models.DecimalField(max_digits=10, decimal_places=4, null=True, blank=True, verbose_name='Fator de Conversão')

    # Pricing
    sale_price = models.DecimalField(max_digits=15, decimal_places=2, null=True, blank=True, verbose_name='Preço de Venda')
    cost_price = models.DecimalField(max_digits=15, decimal_places=2, null=True, blank=True, verbose_name='Preço de Custo')
    currency = models.CharField(max_length=3, default='BRL', verbose_name='Moeda')

    # Inventory
    current_stock = models.DecimalField(max_digits=15, decimal_places=4, default=0, verbose_name='Estoque Atual')
    minimum_stock = models.DecimalField(max_digits=15, decimal_places=4, null=True, blank=True, verbose_name='Estoque Mínimo')
    warehouse_code = models.CharField(max_length=20, null=True, blank=True, verbose_name='Código do Armazém')

    # Tax information
    ncm_code = models.CharField(max_length=20, null=True, blank=True, verbose_name='NCM')
    ipi_percentage = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True, verbose_name='% IPI')
    icms_percentage = models.DecimalField(max_digits=5, decimal_places=2, null=True, blank=True, verbose_name='% ICMS')
    icms_base = models.DecimalField(max_digits=15, decimal_places=2, null=True, blank=True, verbose_name='Base Cálculo ICMS')
    origin = models.CharField(max_length=1, null=True, blank=True, verbose_name='Origem',
                             help_text='0=Nacional, 1=Estrangeira Importação Direta, 2=Estrangeira Mercado Interno')

    # Supplier information
    supplier_code = models.CharField(max_length=50, null=True, blank=True, verbose_name='Código do Fornecedor')
    supplier_name = models.CharField(max_length=255, null=True, blank=True, verbose_name='Nome do Fornecedor')

    # Purchase Order specific fields
    quantity = models.DecimalField(max_digits=15, decimal_places=4, null=True, blank=True, verbose_name='Quantidade')
    unit_value = models.DecimalField(max_digits=15, decimal_places=2, null=True, blank=True, verbose_name='Valor Unitário')
    discount = models.DecimalField(max_digits=15, decimal_places=2, null=True, blank=True, verbose_name='Desconto')

    # Validation fields
    VALIDATION_STATUS_CHOICES = [
        ('PENDING', 'Pendente'),
        ('VALID', 'Válido'),
        ('INVALID', 'Inválido'),
    ]
    validation_status = models.CharField(max_length=10, choices=VALIDATION_STATUS_CHOICES, default='PENDING', verbose_name='Status de Validação')
    product_code_validated = models.BooleanField(default=False, verbose_name='Código Produto Validado')
    supplier_code_validated = models.BooleanField(default=False, verbose_name='Código Fornecedor Validado')
    validation_error = models.TextField(null=True, blank=True, verbose_name='Erro de Validação')

    # Additional fields
    barcode = models.CharField(max_length=50, null=True, blank=True, verbose_name='Código de Barras')
    weight = models.DecimalField(max_digits=10, decimal_places=3, null=True, blank=True, verbose_name='Peso')
    weight_unit = models.CharField(max_length=5, default='KG', verbose_name='Unidade de Peso')

    active = models.BooleanField(default=True, verbose_name='Ativo')
    observations = models.TextField(null=True, blank=True, verbose_name='Observações')

    # Control fields
    created_at = models.DateTimeField(default=timezone.now)
    updated_at = models.DateTimeField(auto_now=True)
    synced_to_protheus = models.BooleanField(default=False, verbose_name='Sincronizado com Protheus')
    protheus_sync_date = models.DateTimeField(null=True, blank=True, verbose_name='Data Sincronização Protheus')
    protheus_error = models.TextField(null=True, blank=True, verbose_name='Erro Protheus')

    # Store raw data from Excel/XML for reference
    raw_data = models.JSONField(null=True, blank=True, verbose_name='Dados Brutos')

    class Meta:
        ordering = ['-created_at']
        verbose_name = 'Produto'
        verbose_name_plural = 'Produtos'
        indexes = [
            models.Index(fields=['product_code', 'batch']),
            models.Index(fields=['synced_to_protheus']),
        ]

    def __str__(self):
        return f"{self.product_code} - {self.description}"
