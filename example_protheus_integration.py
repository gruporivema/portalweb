"""
Exemplo de Script para Integração com TOTVS Protheus

Este script demonstra como consumir a API do Portal e integrar com Protheus.
Você deve adaptar a função cadastrar_produto_protheus() com sua lógica específica.
"""

import requests
from typing import List, Dict
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class PortalProtheusIntegration:
    def __init__(self, portal_api_url: str, portal_username: str, portal_password: str):
        """
        Inicializa a integração com o Portal

        Args:
            portal_api_url: URL base da API (ex: http://seu-dominio.com/api)
            portal_username: Usuário do Portal
            portal_password: Senha do Portal
        """
        self.portal_api_url = portal_api_url.rstrip('/')
        self.portal_auth = (portal_username, portal_password)

    def obter_produtos_pendentes(self, batch_code: str = None) -> List[Dict]:
        """
        Obtém produtos pendentes de sincronização com Protheus

        Args:
            batch_code: Código do lote (opcional). Se não informado, retorna todos pendentes.

        Returns:
            Lista de produtos pendentes
        """
        logger.info("Obtendo produtos pendentes de sincronização...")

        url = f"{self.portal_api_url}/products/pending_sync/"
        params = {}

        if batch_code:
            params['batch_code'] = batch_code

        response = requests.get(url, auth=self.portal_auth, params=params)
        response.raise_for_status()

        data = response.json()
        produtos = data.get('results', [])

        logger.info(f"Encontrados {len(produtos)} produtos pendentes")
        return produtos

    def cadastrar_produto_protheus(self, produto: Dict) -> Dict:
        """
        VOCÊ DEVE IMPLEMENTAR ESTA FUNÇÃO com sua lógica específica de integração com Protheus

        Args:
            produto: Dados do produto do Portal

        Returns:
            Dicionário com resultado do cadastro

        Exemplo de implementação:
        """
        # EXEMPLO - SUBSTITUA COM SUA LÓGICA REAL
        try:
            # Aqui você faria a integração real com Protheus
            # Pode ser via REST API do Protheus, SOAP, ou outro método

            # Exemplo de estrutura de dados para enviar ao Protheus:
            dados_protheus = {
                'B1_COD': produto['product_code'],
                'B1_DESC': produto['description'],
                'B1_TIPO': produto.get('product_type', 'PA'),
                'B1_UM': produto.get('unit_of_measure', 'UN'),
                'B1_LOCPAD': produto.get('warehouse_code', '01'),
                'B1_GRUPO': produto.get('product_group', ''),
                'B1_PRV1': float(produto.get('sale_price') or 0),
                'B1_CUSTD': float(produto.get('cost_price') or 0),
                'B1_POSIPI': produto.get('ncm_code', ''),
                'B1_IPI': float(produto.get('ipi_percentage') or 0),
                'B1_CODBAR': produto.get('barcode', ''),
                # ... outros campos conforme necessário
            }

            # Chamada para API do Protheus (exemplo fictício)
            # response = requests.post(
            #     "http://seu-protheus.com/api/produto",
            #     json=dados_protheus,
            #     headers={"Authorization": "Bearer seu-token"}
            # )
            # response.raise_for_status()

            logger.info(f"Produto {produto['product_code']} cadastrado com sucesso no Protheus")

            return {
                'success': True,
                'product_id': produto['id'],
                'message': 'Produto cadastrado com sucesso'
            }

        except Exception as e:
            logger.error(f"Erro ao cadastrar produto {produto['product_code']}: {str(e)}")
            return {
                'success': False,
                'product_id': produto['id'],
                'error_message': str(e)
            }

    def atualizar_status_sincronizacao(self, updates: List[Dict]) -> Dict:
        """
        Atualiza o status de sincronização dos produtos no Portal

        Args:
            updates: Lista de atualizações no formato:
                     [{"product_id": 1, "success": True}, ...]

        Returns:
            Resposta da API
        """
        logger.info(f"Atualizando status de {len(updates)} produtos...")

        url = f"{self.portal_api_url}/products/update_sync_status/"
        response = requests.post(
            url,
            json={'updates': updates},
            auth=self.portal_auth
        )
        response.raise_for_status()

        data = response.json()
        logger.info(f"Status atualizado: {len(data['results']['success'])} sucessos")

        return data

    def sincronizar_produtos(self, batch_code: str = None, max_produtos: int = None):
        """
        Processo completo de sincronização de produtos com Protheus

        Args:
            batch_code: Código do lote específico (opcional)
            max_produtos: Número máximo de produtos a processar (opcional)
        """
        logger.info("=" * 60)
        logger.info("INICIANDO SINCRONIZAÇÃO COM PROTHEUS")
        logger.info("=" * 60)

        # 1. Obter produtos pendentes
        produtos = self.obter_produtos_pendentes(batch_code)

        if not produtos:
            logger.info("Nenhum produto pendente encontrado")
            return

        if max_produtos:
            produtos = produtos[:max_produtos]
            logger.info(f"Limitando processamento a {max_produtos} produtos")

        # 2. Processar cada produto
        updates = []
        total = len(produtos)
        sucesso = 0
        erro = 0

        for idx, produto in enumerate(produtos, 1):
            logger.info(f"[{idx}/{total}] Processando {produto['product_code']}...")

            resultado = self.cadastrar_produto_protheus(produto)

            if resultado['success']:
                sucesso += 1
                updates.append({
                    'product_id': produto['id'],
                    'success': True
                })
            else:
                erro += 1
                updates.append({
                    'product_id': produto['id'],
                    'success': False,
                    'error_message': resultado.get('error_message', 'Erro desconhecido')
                })

        # 3. Atualizar status no Portal
        if updates:
            self.atualizar_status_sincronizacao(updates)

        # 4. Resumo
        logger.info("=" * 60)
        logger.info("SINCRONIZAÇÃO CONCLUÍDA")
        logger.info(f"Total processado: {total}")
        logger.info(f"Sucessos: {sucesso}")
        logger.info(f"Erros: {erro}")
        logger.info("=" * 60)


def main():
    """
    Exemplo de uso
    """
    # Configurações do Portal
    PORTAL_API_URL = "http://127.0.0.1:8000/api"
    PORTAL_USERNAME = "seu_usuario"
    PORTAL_PASSWORD = "sua_senha"

    # Criar instância da integração
    integration = PortalProtheusIntegration(
        portal_api_url=PORTAL_API_URL,
        portal_username=PORTAL_USERNAME,
        portal_password=PORTAL_PASSWORD
    )

    # Opção 1: Sincronizar todos os produtos pendentes
    integration.sincronizar_produtos()

    # Opção 2: Sincronizar apenas um lote específico
    # integration.sincronizar_produtos(batch_code="BATCH-20231215143022-a1b2c3d4")

    # Opção 3: Sincronizar no máximo 10 produtos por vez
    # integration.sincronizar_produtos(max_produtos=10)


if __name__ == "__main__":
    main()
