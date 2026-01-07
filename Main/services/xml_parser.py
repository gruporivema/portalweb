import xml.etree.ElementTree as ET
from decimal import Decimal
from typing import Dict, List, Any
import logging

logger = logging.getLogger(__name__)


class XMLParser:

    TAG_MAPPING = {
        'product_code': ['codigo', 'cod', 'product_code', 'codigo_produto', 'productCode'],
        'description': ['descricao', 'desc', 'description', 'produto', 'nome'],
        'short_description': ['descricao_curta', 'desc_curta', 'shortDescription'],
        'product_type': ['tipo', 'type', 'product_type', 'productType'],
        'product_group': ['grupo', 'group', 'product_group', 'productGroup'],
        'product_category': ['categoria', 'category', 'product_category'],
        'unit_of_measure': ['unidade', 'um', 'unit', 'unitOfMeasure'],
        'second_unit': ['segunda_unidade', 'secondUnit'],
        'conversion_factor': ['fator_conversao', 'conversionFactor', 'fator'],
        'sale_price': ['preco_venda', 'preco', 'price', 'salePrice', 'valor'],
        'cost_price': ['preco_custo', 'custo', 'cost', 'costPrice'],
        'currency': ['moeda', 'currency'],
        'current_stock': ['estoque', 'stock', 'currentStock', 'qtd', 'quantidade'],
        'minimum_stock': ['estoque_minimo', 'minimumStock', 'minStock'],
        'warehouse_code': ['armazem', 'warehouse', 'warehouseCode', 'local'],
        'ncm_code': ['ncm', 'codigo_ncm', 'ncmCode'],
        'ipi_percentage': ['ipi', 'ipi_percentage', 'percentualIpi', 'vIPI', 'pIPI', 'aliq_ipi', 'aliqIPI'],
        'icms_percentage': ['icms', 'icms_percentage', 'percentualIcms', 'vICMS', 'pICMS', 'aliq_icms', 'aliqICMS'],
        'icms_base': ['icms_base', 'base_icms', 'vBC', 'baseCalculo', 'baseCalculoIcms'],
        'origin': ['origem', 'origin', 'prod_origem', 'orig'],
        'quantity': ['quantidade', 'quant', 'qtd', 'qty', 'quantity', 'qCom'],
        'unit_value': ['valor_unitario', 'valorUnitario', 'vUnCom', 'unit_value', 'precoUnitario'],
        'discount': ['desconto', 'discount', 'vDesc'],
        'supplier_code': ['fornecedor_codigo', 'cod_fornecedor', 'supplierCode'],
        'supplier_name': ['fornecedor_nome', 'fornecedor', 'supplier', 'supplierName'],
        'barcode': ['codigo_barras', 'barcode', 'ean'],
        'weight': ['peso', 'weight'],
        'weight_unit': ['peso_unidade', 'weightUnit'],
        'active': ['ativo', 'active', 'status'],
        'observations': ['observacoes', 'obs', 'observations', 'notas'],
    }

    def __init__(self, file_path: str):
        self.file_path = file_path
        self.root = None

    def parse(self) -> List[Dict[str, Any]]:
        try:
            tree = ET.parse(self.file_path)
            self.root = tree.getroot()

            products = []

            product_elements = self._find_product_elements()

            for product_elem in product_elements:
                try:
                    product_data = self._extract_product_data(product_elem)
                    if product_data.get('product_code') and product_data.get('description'):
                        products.append(product_data)
                    else:
                        logger.warning(f"Produto ignorado: falta código ou descrição")
                except Exception as e:
                    logger.error(f"Erro ao processar elemento de produto: {str(e)}")
                    continue

            logger.info(f"Total de {len(products)} produtos extraídos do XML")
            return products

        except Exception as e:
            logger.error(f"Erro ao analisar arquivo XML: {str(e)}")
            raise

    def _find_product_elements(self) -> List[ET.Element]:
        possible_tags = ['product', 'produto', 'item', 'Product', 'Produto', 'Item']

        for tag in possible_tags:
            elements = self.root.findall(f'.//{tag}')
            if elements:
                return elements

        if len(list(self.root)) > 0:
            return list(self.root)

        return []

    def _find_element_value(self, element: ET.Element, field_name: str, default=None) -> Any:
        if field_name not in self.TAG_MAPPING:
            return default

        possible_tags = self.TAG_MAPPING[field_name]

        for tag in possible_tags:
            child = element.find(tag)
            if child is not None:
                value = child.text
                if value:
                    return value.strip()

            if tag in element.attrib:
                return element.attrib[tag].strip()

        for tag in possible_tags:
            for child in element:
                if child.tag.lower() == tag.lower():
                    value = child.text
                    if value:
                        return value.strip()

        return default

    def _extract_product_data(self, element: ET.Element) -> Dict[str, Any]:
        product_data = {
            'product_code': self._find_element_value(element, 'product_code', ''),
            'description': self._find_element_value(element, 'description', ''),
            'short_description': self._find_element_value(element, 'short_description') or None,
            'product_type': self._find_element_value(element, 'product_type') or None,
            'product_group': self._find_element_value(element, 'product_group') or None,
            'product_category': self._find_element_value(element, 'product_category') or None,
            'unit_of_measure': self._find_element_value(element, 'unit_of_measure') or None,
            'second_unit': self._find_element_value(element, 'second_unit') or None,
            'conversion_factor': self._parse_decimal(self._find_element_value(element, 'conversion_factor')),
            'sale_price': self._parse_decimal(self._find_element_value(element, 'sale_price')),
            'cost_price': self._parse_decimal(self._find_element_value(element, 'cost_price')),
            'currency': self._find_element_value(element, 'currency', 'BRL'),
            'current_stock': self._parse_decimal(self._find_element_value(element, 'current_stock', '0')),
            'minimum_stock': self._parse_decimal(self._find_element_value(element, 'minimum_stock')),
            'warehouse_code': self._find_element_value(element, 'warehouse_code') or None,
            'ncm_code': self._find_element_value(element, 'ncm_code') or None,
            'ipi_percentage': self._parse_decimal(self._find_element_value(element, 'ipi_percentage')),
            'icms_percentage': self._parse_decimal(self._find_element_value(element, 'icms_percentage')),
            'icms_base': self._parse_decimal(self._find_element_value(element, 'icms_base')),
            'origin': self._find_element_value(element, 'origin') or None,
            'quantity': self._parse_decimal(self._find_element_value(element, 'quantity')),
            'unit_value': self._parse_decimal(self._find_element_value(element, 'unit_value')),
            'discount': self._parse_decimal(self._find_element_value(element, 'discount')),
            'supplier_code': self._find_element_value(element, 'supplier_code') or None,
            'supplier_name': self._find_element_value(element, 'supplier_name') or None,
            'barcode': self._find_element_value(element, 'barcode') or None,
            'weight': self._parse_decimal(self._find_element_value(element, 'weight')),
            'weight_unit': self._find_element_value(element, 'weight_unit', 'KG'),
            'active': self._parse_boolean(self._find_element_value(element, 'active', 'True')),
            'observations': self._find_element_value(element, 'observations') or None,
        }

        raw_data = {}
        for child in element:
            raw_data[child.tag] = child.text
        product_data['raw_data'] = raw_data

        return product_data

    def _parse_decimal(self, value, default=None) -> Decimal:
        if value is None or value == '':
            return default

        try:
            if isinstance(value, str):
                value = value.replace(',', '.')
                value = value.replace(' ', '')

            decimal_value = Decimal(str(value))
            return decimal_value
        except Exception:
            return default

    def _parse_boolean(self, value, default=True) -> bool:
        if value is None or value == '':
            return default

        if isinstance(value, bool):
            return value

        if isinstance(value, str):
            value = value.strip().lower()
            if value in ['true', 'sim', 's', 'yes', 'y', '1', 'ativo']:
                return True
            elif value in ['false', 'nao', 'não', 'n', 'no', '0', 'inativo']:
                return False

        return default
