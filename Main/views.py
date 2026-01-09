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
    View para entrada de fornecedor e grupo de produtos
    """
    batch = get_object_or_404(ProductBatch, batch_code=batch_code)

    if request.method == 'POST':
        # Get fornecedor code and product group from user input
        fornecedor_code = request.POST.get('fornecedor_code', '').strip()
        product_group = request.POST.get('product_group', '').strip()

        # Save to batch
        if fornecedor_code:
            batch.fornecedor_code = fornecedor_code
        if product_group:
            batch.product_group = product_group

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
    Aplica normalização antes da validação
    """
    if request.method == 'POST':
        product_ids = request.POST.getlist('product_ids[]')

        for product_id in product_ids:
            product = Product.objects.get(pk=product_id)

            # Get batch-level product_group and fornecedor for normalization
            batch = product.batch
            product_group = batch.product_group
            fornecedor = batch.fornecedor_code

            # Store original code for reference
            original_code = product.product_code

            # Normalize product code based on GRUPO and FORNECEDOR
            normalized_code = normalize_product_code(original_code, product_group, fornecedor)

            # Update product code with normalized value
            product.product_code = normalized_code

            # Special handling for GRUPO 0007 (TATU): try without dots first, then with dots
            if product_group == "0007" and fornecedor == "TATU":
                # First attempt: validate without dots
                product_valid = validate_product_code(normalized_code, product_group)

                # If validation fails, try with dots
                if not product_valid:
                    code_with_dots = normalize_product_code_with_dots_0007(normalized_code)
                    product.product_code = code_with_dots
                    product_valid = validate_product_code(code_with_dots, product_group)
            else:
                # Standard validation for other groups
                product_valid = validate_product_code(normalized_code, product_group)

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


def normalize_product_code(product_code, product_group, fornecedor):
    """
    Normaliza o código do produto baseado no grupo e fornecedor

    Args:
        product_code (str): Código original do produto
        product_group (str): Grupo de produtos selecionado
        fornecedor (str): Fornecedor selecionado

    Returns:
        str: Código normalizado (ou original se não houver regra)
    """
    if not product_code:
        return product_code

    # Remove espaços em branco
    code = str(product_code).strip()

    # GRUPO 0052 (JF)
    if product_group == "0052" and fornecedor == "JF":
        # Remove letras e mantém apenas números
        numbers_only = ''.join(filter(str.isdigit, code))
        # Garante 8 números (pad com zeros à direita se necessário)
        numbers_only = numbers_only.ljust(8, '0')[:8]
        # Adiciona ponto após os primeiros 2 números
        if len(numbers_only) >= 2:
            return f"{numbers_only[:2]}.{numbers_only[2:]}"
        return numbers_only

    # GRUPO 0009 (VENCE TUDO) - Sem mudanças
    elif product_group == "0009":
        return code

    # GRUPO 0008 (JAN)
    elif product_group == "0008" and fornecedor == "JAN":
        # Remove tudo que não é número
        numbers_only = ''.join(filter(str.isdigit, code))
        # Deve ter 18 números, remove os primeiros 10
        if len(numbers_only) >= 18:
            last_8 = numbers_only[10:18]
        else:
            # Se não tem 18, usa os últimos 8 disponíveis
            last_8 = numbers_only[-8:] if len(numbers_only) >= 8 else numbers_only.zfill(8)

        # Formata: XXX.XX.XXX
        if len(last_8) >= 8:
            return f"{last_8[:3]}.{last_8[3:5]}.{last_8[5:]}"
        return last_8

    # GRUPO 0007 (TATU) - Retorna código sem formatação (validação dual será feita depois)
    elif product_group == "0007" and fornecedor == "TATU":
        # Remove tudo que não é número
        numbers_only = ''.join(filter(str.isdigit, code))
        return numbers_only

    # GRUPO 0005 (MACDON)
    elif product_group == "0005" and fornecedor == "MACDON":
        # Remove zero inicial se existir
        while code.startswith('0') and len(code) > 1:
            code = code[1:]
        return code

    # GRUPO 0004 (JUMIL)
    elif product_group == "0004" and fornecedor == "JUMIL":
        # Remove tudo que não é número
        numbers_only = ''.join(filter(str.isdigit, code))
        # Pad com zeros à esquerda se necessário para ter 7 dígitos
        numbers_only = numbers_only.zfill(7)
        # Formata: XX.XX.XXX
        if len(numbers_only) >= 7:
            return f"{numbers_only[:2]}.{numbers_only[2:4]}.{numbers_only[4:7]}"
        return numbers_only

    # GRUPO 0003 (JACTO)
    elif product_group == "0003" and fornecedor == "JACTO":
        # Remove tudo que não é número
        numbers_only = ''.join(filter(str.isdigit, code))

        if len(numbers_only) == 4:
            # 4 dígitos: 001.164 (preenche com zeros na frente)
            return f"00{numbers_only[0]}.{numbers_only[1:]}"
        elif len(numbers_only) == 7:
            # 7 dígitos: 125.5351
            return f"{numbers_only[:3]}.{numbers_only[3:]}"
        else:
            # Tenta detectar o padrão baseado no tamanho
            if len(numbers_only) <= 4:
                padded = numbers_only.zfill(4)
                return f"00{padded[0]}.{padded[1:]}"
            else:
                # Assume formato de 7 dígitos
                return f"{numbers_only[:3]}.{numbers_only[3:]}"

    # GRUPO 0002 (KUHN) - Sem mudanças
    elif product_group == "0002" and fornecedor == "KUHN":
        return code

    # GRUPO 0001 (HORSH) - Sem mudanças
    elif product_group == "0001" and fornecedor == "HORSH":
        return code

    # OUTROS - Sem mudanças
    elif product_group == "OUTROS" or fornecedor == "OUTROS":
        return code

    # Se não houver regra específica, retorna código original
    return code


def normalize_product_code_with_dots_0007(product_code):
    """
    Normaliza código do GRUPO 0007 (TATU) com pontos: XXX.XXXX.XXX

    Args:
        product_code (str): Código do produto (apenas números)

    Returns:
        str: Código formatado com pontos
    """
    # Remove tudo que não é número
    numbers_only = ''.join(filter(str.isdigit, str(product_code)))

    # Formata: XXX.XXXX.XXX
    if len(numbers_only) >= 10:
        return f"{numbers_only[:3]}.{numbers_only[3:7]}.{numbers_only[7:10]}"
    elif len(numbers_only) >= 7:
        # Se tiver menos de 10, tenta adaptar
        return f"{numbers_only[:3]}.{numbers_only[3:7]}.{numbers_only[7:]}"

    return numbers_only


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
    Submete apenas produtos VALIDADOS para Protheus via API REST
    Cria um Pedido de Compra no Protheus usando MATA120
    """
    import requests
    from datetime import datetime
    from django.conf import settings

    batch = get_object_or_404(ProductBatch, batch_code=batch_code)

    # Apenas POST é permitido
    if request.method != 'POST':
        messages.error(request, "Método não permitido.")
        return redirect('Main:validation_table', batch_code=batch_code)

    # Recebe dados do formulário modal
    filial = request.POST.get('filial', '').strip()
    loja = request.POST.get('loja', '').strip()
    condicao_pagamento = request.POST.get('condicao_pagamento', '').strip()
    data_emissao = request.POST.get('data_emissao', '').strip()

    # Validações básicas
    if not filial:
        messages.error(request, "Filial (TENANTID) é obrigatória.")
        return redirect('Main:validation_table', batch_code=batch_code)

    if not loja:
        messages.error(request, "Loja do fornecedor é obrigatória.")
        return redirect('Main:validation_table', batch_code=batch_code)

    if not condicao_pagamento:
        messages.error(request, "Condição de pagamento é obrigatória.")
        return redirect('Main:validation_table', batch_code=batch_code)

    # Filtra apenas produtos com status VALID
    valid_products = Product.objects.filter(batch=batch, validation_status='VALID')

    if valid_products.count() == 0:
        messages.warning(request, "Nenhum produto válido para submeter ao Protheus.")
        return redirect('Main:validation_table', batch_code=batch_code)

    # Pega o fornecedor do primeiro produto válido
    fornecedor = valid_products.first().supplier_code
    if not fornecedor:
        messages.error(request, "Código do fornecedor não encontrado nos produtos.")
        return redirect('Main:validation_table', batch_code=batch_code)

    # Formata data de emissão (se fornecida)
    if data_emissao:
        try:
            # Converte formato YYYY-MM-DD para DD/MM/YYYY
            data_obj = datetime.strptime(data_emissao, '%Y-%m-%d')
            data_emissao_formatada = data_obj.strftime('%d/%m/%Y')
        except ValueError:
            data_emissao_formatada = datetime.now().strftime('%d/%m/%Y')
    else:
        data_emissao_formatada = datetime.now().strftime('%d/%m/%Y')

    # Monta array de itens
    itens = []
    for product in valid_products:
        item = {
            "produto": product.product_code,
            "quantidade": float(product.quantity) if product.quantity else 1.0,
            "preco": float(product.unit_value) if product.unit_value else 0.0,
            "total": float(product.quantity or 1.0) * float(product.unit_value or 0.0)
        }
        itens.append(item)

    # Monta payload para API Protheus
    payload = {
        "fornecedor": fornecedor,
        "loja": loja,
        "condicao_pagamento": condicao_pagamento,
        "data_emissao": data_emissao_formatada,
        "itens": itens
    }

    # URL da API Protheus (configurável via settings)
    protheus_api_url = getattr(settings, 'PROTHEUS_API_URL', 'http://localhost:8080')
    api_endpoint = f"{protheus_api_url}/rest/PRODCHECK/createPedidoCompra"

    try:
        # Chama API Protheus com header TENANTID
        response = requests.post(
            api_endpoint,
            json=payload,
            headers={
                'Content-Type': 'application/json',
                'tenantid': filial
            },
            timeout=30
        )

        if response.status_code == 200:
            # Sucesso - marca produtos como sincronizados
            response_data = response.json()
            numero_pedido = response_data.get('numero_pedido', 'N/A')

            for product in valid_products:
                product.synced_to_protheus = True
                product.protheus_sync_date = datetime.now()
                product.save()

            batch.synced_to_protheus = True
            batch.save()

            messages.success(
                request,
                f"Pedido de Compra {numero_pedido} criado com sucesso! "
                f"{valid_products.count()} produto(s) sincronizado(s)."
            )
        else:
            # Erro na API
            error_message = response.text if response.text else f"Erro HTTP {response.status_code}"
            messages.error(
                request,
                f"Erro ao criar Pedido de Compra no Protheus: {error_message}"
            )
            return redirect('Main:validation_table', batch_code=batch_code)

    except requests.exceptions.Timeout:
        messages.error(request, "Timeout ao conectar com API Protheus. Tente novamente.")
        return redirect('Main:validation_table', batch_code=batch_code)

    except requests.exceptions.ConnectionError:
        messages.error(request, "Erro de conexão com API Protheus. Verifique a URL e conectividade.")
        return redirect('Main:validation_table', batch_code=batch_code)

    except Exception as e:
        messages.error(request, f"Erro ao submeter ao Protheus: {str(e)}")
        return redirect('Main:validation_table', batch_code=batch_code)

    return redirect('Main:product_list')
