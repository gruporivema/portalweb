from django.shortcuts import render, redirect, get_object_or_404
from django.contrib import messages
from django.contrib.auth import authenticate, login as auth_login, logout as auth_logout
from django.contrib.auth.decorators import login_required
from django.core.paginator import Paginator
from django.db.models import Q
from django.http import JsonResponse
import requests

from .models import FileUpload, ProductBatch, Product
from .forms import FileUploadForm
from .services.file_processor import process_uploaded_file


def login_view(request):
    """
    View para login de usuários
    """
    # Se já está autenticado, redireciona para o upload
    if request.user.is_authenticated:
        return redirect('Main:upload_file')

    if request.method == 'POST':
        username = request.POST.get('username')
        password = request.POST.get('password')

        user = authenticate(request, username=username, password=password)

        if user is not None:
            auth_login(request, user)
            messages.success(request, f'Bem-vindo, {user.username}!')

            # Redireciona para a próxima página ou upload
            next_url = request.GET.get('next', 'Main:upload_file')
            return redirect(next_url)
        else:
            messages.error(request, 'Usuário ou senha inválidos.')

    return render(request, 'Main/login.html')


def logout_view(request):
    """
    View para logout de usuários
    """
    auth_logout(request)
    messages.info(request, 'Você saiu do sistema.')
    return redirect('Main:login')


@login_required
def upload_file(request):
    """
    View para upload de arquivos Excel/XML
    """
    if request.method == 'POST':
        form = FileUploadForm(request.POST, request.FILES)
        if form.is_valid():
            file = request.FILES['file']
            file_type = form.cleaned_data['file_type']

            user = request.user if request.user.is_authenticated else None

            result = process_uploaded_file(file, file_type, user)

            if result['success']:
                messages.success(
                    request,
                    f"Arquivo processado com sucesso! {result['saved']} de {result['total']} produtos salvos."
                )
                # Redirect to filter selection page
                return redirect('Main:filter_selection', batch_code=result['batch_code'])
            else:
                messages.error(
                    request,
                    f"Erro ao processar arquivo: {result['message']}"
                )
    else:
        form = FileUploadForm()

    context = {
        'form': form,
    }
    return render(request, 'Main/upload_file.html', context)


@login_required
def product_list(request):
    """
    View para listar produtos
    """
    search_query = request.GET.get('search', '')
    batch_filter = request.GET.get('batch', '')
    sync_filter = request.GET.get('sync', '')

    products = Product.objects.select_related('batch').all()

    if search_query:
        products = products.filter(
            Q(product_code__icontains=search_query) |
            Q(description__icontains=search_query) |
            Q(barcode__icontains=search_query) |
            Q(supplier_name__icontains=search_query)
        )

    if batch_filter:
        products = products.filter(batch__batch_code=batch_filter)

    if sync_filter == 'synced':
        products = products.filter(synced_to_protheus=True)
    elif sync_filter == 'pending':
        products = products.filter(synced_to_protheus=False)

    products = products.order_by('-created_at')

    paginator = Paginator(products, 25)
    page_number = request.GET.get('page')
    page_obj = paginator.get_page(page_number)

    batches = ProductBatch.objects.all().order_by('-created_at')

    context = {
        'page_obj': page_obj,
        'search_query': search_query,
        'batch_filter': batch_filter,
        'sync_filter': sync_filter,
        'batches': batches,
    }
    return render(request, 'Main/product_list.html', context)


@login_required
def product_detail(request, pk):
    """
    View para detalhes de um produto
    """
    product = get_object_or_404(Product, pk=pk)

    context = {
        'product': product,
    }
    return render(request, 'Main/product_detail.html', context)


@login_required
def upload_history(request):
    """
    View para histórico de uploads
    """
    uploads = FileUpload.objects.all().order_by('-uploaded_at')

    paginator = Paginator(uploads, 20)
    page_number = request.GET.get('page')
    page_obj = paginator.get_page(page_number)

    context = {
        'page_obj': page_obj,
    }
    return render(request, 'Main/upload_history.html', context)


@login_required
def filter_selection(request, batch_code):
    """
    View para entrada de código do fornecedor
    """
    batch = get_object_or_404(ProductBatch, batch_code=batch_code)

    if request.method == 'POST':
        # Get fornecedor code from user input and save to batch
        fornecedor_code = request.POST.get('fornecedor_code', '').strip()
        if fornecedor_code:
            batch.fornecedor_code = fornecedor_code
            batch.save()

        # Redirect to validation table
        return redirect('Main:validation_table', batch_code=batch_code)

    context = {
        'batch': batch,
    }
    return render(request, 'Main/filter_selection.html', context)


@login_required
def validation_table(request, batch_code):
    """
    View para exibir tabela de produtos com validação
    """
    batch = get_object_or_404(ProductBatch, batch_code=batch_code)

    # Get all products in the batch
    products = Product.objects.filter(batch=batch).order_by('product_code')

    # Check if all products are validated
    all_validated = all(
        p.product_code_validated and p.supplier_code_validated
        for p in products
    ) if products.exists() else False

    # Get fornecedor from batch (for display)
    fornecedor_code = batch.fornecedor_code or 'Não informado'

    context = {
        'batch': batch,
        'products': products,
        'fornecedor_code': fornecedor_code,
        'all_validated': all_validated,
    }
    return render(request, 'Main/validation_table.html', context)


@login_required
def validate_codes(request):
    """
    API endpoint para validar códigos de produto e fornecedor
    """
    if request.method == 'POST':
        product_ids = request.POST.getlist('product_ids[]')

        for product_id in product_ids:
            product = Product.objects.get(pk=product_id)

            # Validate product code
            product_valid = validate_product_code(product.product_code, product.product_group)
            product.product_code_validated = product_valid

            # Validate supplier code
            supplier_valid = validate_supplier_code(product.supplier_code)
            product.supplier_code_validated = supplier_valid

            # Apply validation rules
            validation_errors = []

            # Rule 1: Check if product registration exists
            if not product_valid:
                validation_errors.append(f"Produto {product.product_code} não encontrado no cadastro")

            # Rule 2: ICMS 4% validation (XML only)
            if hasattr(product.batch.file_upload, 'file_type') and product.batch.file_upload.file_type == 'XML':
                if product.icms_percentage == 4 and product.origin != '2':
                    validation_errors.append("ICMS 4% requer Origem = 2")

            # Rule 3: IPI validation (XML only)
            if hasattr(product.batch.file_upload, 'file_type') and product.batch.file_upload.file_type == 'XML':
                if product.ipi_percentage:
                    # Here you would check against registered IPI percentage
                    # For now, we'll skip this check
                    pass

            # Set validation status
            if validation_errors:
                product.validation_status = 'INVALID'
                product.validation_error = '; '.join(validation_errors)
            elif product_valid and supplier_valid:
                product.validation_status = 'VALID'
                product.validation_error = None
            else:
                product.validation_status = 'PENDING'

            product.save()

        return JsonResponse({'success': True})

    return JsonResponse({'success': False}, status=400)


def validate_product_code(product_code, product_group):
    """
    Valida se o código do produto existe no cadastro do Protheus

    IMPORTANTE: Esta função é um PLACEHOLDER que sempre retorna True
    VOCÊ PRECISA IMPLEMENTAR A CHAMADA PARA SUA API PROTHEUS AQUI

    Args:
        product_code (str): Código do produto a validar
        product_group (str): Grupo do produto para filtrar busca

    Returns:
        bool: True se código existe no Protheus, False caso contrário

    Exemplo de implementação:
        try:
            response = requests.get(
                'https://sua-api-protheus.com/produtos',
                params={
                    'codigo': product_code,
                    'grupo': product_group
                },
                headers={'Authorization': f'Bearer {seu_token}'},
                timeout=10
            )
            return response.status_code == 200 and response.json().get('exists', False)
        except Exception as e:
            print(f'Erro ao validar produto: {e}')
            return False
    """
    # TODO: REMOVA ESTA LINHA e adicione sua chamada de API acima
    return True


def validate_supplier_code(supplier_code):
    """
    Valida se o código do fornecedor existe no cadastro do Protheus

    IMPORTANTE: Esta função é um PLACEHOLDER que sempre retorna True
    VOCÊ PRECISA IMPLEMENTAR A CHAMADA PARA SUA API PROTHEUS AQUI

    Args:
        supplier_code (str): Código do fornecedor a validar

    Returns:
        bool: True se código existe no Protheus, False caso contrário

    Exemplo de implementação:
        try:
            response = requests.get(
                'https://sua-api-protheus.com/fornecedores',
                params={'codigo': supplier_code},
                headers={'Authorization': f'Bearer {seu_token}'},
                timeout=10
            )
            return response.status_code == 200 and response.json().get('exists', False)
        except Exception as e:
            print(f'Erro ao validar fornecedor: {e}')
            return False
    """
    # TODO: REMOVA ESTA LINHA e adicione sua chamada de API acima
    return True


@login_required
def reprocess_batch(request, batch_code):
    """
    Reprocessa validação de um lote
    """
    batch = get_object_or_404(ProductBatch, batch_code=batch_code)

    # Reset validation status for all products in batch
    Product.objects.filter(batch=batch).update(
        validation_status='PENDING',
        product_code_validated=False,
        supplier_code_validated=False,
        validation_error=None
    )

    messages.info(request, "Lote marcado para reprocessamento. Valide novamente os códigos.")

    return redirect('Main:product_list')


@login_required
def submit_to_protheus(request, batch_code):
    """
    Submete apenas produtos VALIDADOS para Protheus
    Produtos com status PENDING ou INVALID são ignorados
    """
    batch = get_object_or_404(ProductBatch, batch_code=batch_code)

    # Filtra apenas produtos com status VALID
    valid_products = Product.objects.filter(batch=batch, validation_status='VALID')

    if valid_products.count() == 0:
        messages.warning(request, "Nenhum produto válido para submeter ao Protheus.")
        return redirect('Main:validation_table', batch_code=batch_code)

    # TODO: ADICIONE AQUI A URL DA SUA API PROTHEUS
    # Exemplo de requisição para cada produto:
    # for product in valid_products:
    #     response = requests.post(
    #         'https://sua-api-protheus.com/pedido-compra',
    #         headers={'Authorization': f'Bearer {token}'},
    #         json={
    #             'codigo': product.product_code,
    #             'quantidade': product.quantity,
    #             'valor_unitario': product.unit_value,
    #             'fornecedor': product.supplier_code,
    #             # ... outros campos
    #         }
    #     )
    #     if response.status_code == 200:
    #         product.synced_to_protheus = True
    #         product.save()

    # Por enquanto, apenas marca como sincronizado (PLACEHOLDER)
    for product in valid_products:
        product.synced_to_protheus = True
        product.save()

    batch.synced_to_protheus = True
    batch.save()

    messages.success(
        request,
        f"{valid_products.count()} produto(s) válido(s) submetido(s) ao Protheus com sucesso!"
    )

    return redirect('Main:product_list')
