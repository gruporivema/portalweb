from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from django.utils import timezone
from django.db.models import Q

from Main.models import Product, ProductBatch, FileUpload
from .serializers import (
    ProductSerializer,
    ProductBatchSerializer,
    FileUploadSerializer,
    ProductSyncSerializer,
    ProductSyncUpdateSerializer
)


class ProductViewSet(viewsets.ModelViewSet):
    queryset = Product.objects.select_related('batch').all()
    serializer_class = ProductSerializer
    permission_classes = [IsAuthenticated]
    filterset_fields = ['synced_to_protheus', 'active', 'product_type', 'product_group']
    search_fields = ['product_code', 'description', 'barcode', 'supplier_name']
    ordering_fields = ['created_at', 'product_code', 'description', 'sale_price']
    ordering = ['-created_at']

    @action(detail=False, methods=['get'])
    def pending_sync(self, request):
        """
        Retorna todos os produtos pendentes de sincronização com Protheus
        """
        products = self.queryset.filter(synced_to_protheus=False)

        batch_code = request.query_params.get('batch_code', None)
        if batch_code:
            products = products.filter(batch__batch_code=batch_code)

        serializer = self.get_serializer(products, many=True)
        return Response({
            'count': products.count(),
            'results': serializer.data
        })

    @action(detail=False, methods=['post'])
    def sync(self, request):
        """
        Retorna produtos para sincronização com Protheus
        """
        serializer = ProductSyncSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)

        product_ids = serializer.validated_data.get('product_ids', [])
        batch_code = serializer.validated_data.get('batch_code', None)

        if product_ids:
            products = self.queryset.filter(id__in=product_ids, synced_to_protheus=False)
        elif batch_code:
            products = self.queryset.filter(batch__batch_code=batch_code, synced_to_protheus=False)
        else:
            products = self.queryset.filter(synced_to_protheus=False)

        product_serializer = self.get_serializer(products, many=True)

        return Response({
            'count': products.count(),
            'products': product_serializer.data
        })

    @action(detail=False, methods=['post'])
    def update_sync_status(self, request):
        """
        Atualiza o status de sincronização dos produtos após integração com Protheus
        """
        updates = request.data.get('updates', [])

        if not updates or not isinstance(updates, list):
            return Response(
                {'error': 'É necessário fornecer uma lista de atualizações'},
                status=status.HTTP_400_BAD_REQUEST
            )

        results = {
            'success': [],
            'failed': [],
            'not_found': []
        }

        for update_data in updates:
            serializer = ProductSyncUpdateSerializer(data=update_data)
            if not serializer.is_valid():
                results['failed'].append({
                    'data': update_data,
                    'error': serializer.errors
                })
                continue

            product_id = serializer.validated_data['product_id']
            success = serializer.validated_data['success']
            error_message = serializer.validated_data.get('error_message', None)

            try:
                product = Product.objects.get(id=product_id)

                if success:
                    product.synced_to_protheus = True
                    product.protheus_sync_date = timezone.now()
                    product.protheus_error = None
                else:
                    product.protheus_error = error_message

                product.save()

                results['success'].append({
                    'product_id': product_id,
                    'product_code': product.product_code
                })

            except Product.DoesNotExist:
                results['not_found'].append(product_id)

        return Response({
            'message': 'Atualização de sincronização processada',
            'results': results
        })

    @action(detail=True, methods=['post'])
    def mark_synced(self, request, pk=None):
        """
        Marca um produto específico como sincronizado
        """
        product = self.get_object()
        product.synced_to_protheus = True
        product.protheus_sync_date = timezone.now()
        product.protheus_error = None
        product.save()

        return Response({
            'message': f'Produto {product.product_code} marcado como sincronizado',
            'product': self.get_serializer(product).data
        })


class ProductBatchViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = ProductBatch.objects.all().order_by('-created_at')
    serializer_class = ProductBatchSerializer
    permission_classes = [IsAuthenticated]
    lookup_field = 'batch_code'

    @action(detail=True, methods=['get'])
    def products(self, request, batch_code=None):
        """
        Retorna todos os produtos de um lote específico
        """
        batch = self.get_object()
        products = batch.products.all()

        serializer = ProductSerializer(products, many=True)
        return Response({
            'batch_code': batch.batch_code,
            'total_products': products.count(),
            'products': serializer.data
        })

    @action(detail=True, methods=['post'])
    def mark_synced(self, request, batch_code=None):
        """
        Marca todo o lote como sincronizado
        """
        batch = self.get_object()

        batch.products.update(
            synced_to_protheus=True,
            protheus_sync_date=timezone.now(),
            protheus_error=None
        )

        batch.synced_to_protheus = True
        batch.synced_at = timezone.now()
        batch.save()

        return Response({
            'message': f'Lote {batch.batch_code} marcado como sincronizado',
            'batch': self.get_serializer(batch).data
        })


class FileUploadViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = FileUpload.objects.all().order_by('-uploaded_at')
    serializer_class = FileUploadSerializer
    permission_classes = [IsAuthenticated]
    filterset_fields = ['file_type', 'status']
    ordering = ['-uploaded_at']
