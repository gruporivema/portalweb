import pandas as pd
from decimal import Decimal
from typing import Dict, List, Any
import logging

logger = logging.getLogger(__name__)


class ExcelParser:

    COLUMN_MAPPING = {
        'codigo': ['codigo', 'cod', 'product_code', 'codigo_produto', 'codigo produto', 'código', 'código do produto', 'cod bruto', 'cod "bruto"', 'codigo bruto'],
        'descricao': ['descricao', 'desc', 'description', 'produto', 'nome', 'descrição', 'descrição do produto'],
        'descricao_curta': ['descricao_curta', 'desc_curta', 'short_description', 'descrição curta'],
        'tipo': ['tipo', 'type', 'product_type', 'tipo_produto', 'tipo produto'],
        'grupo': ['grupo', 'group', 'product_group', 'categoria'],
        'categoria': ['categoria', 'category', 'product_category', 'subcategoria'],
        'unidade': ['unidade', 'um', 'unit', 'unit_of_measure', 'unidade_medida', 'unidade de medida', 'un'],
        'segunda_unidade': ['segunda_unidade', 'second_unit', '2_unidade', 'segunda un'],
        'fator_conversao': ['fator_conversao', 'conversion_factor', 'fator', 'fator de conversão'],
        'preco_venda': ['preco_venda', 'preco', 'price', 'sale_price', 'valor', 'preço', 'preço de venda', 'preco venda'],
        'preco_custo': ['preco_custo', 'custo', 'cost', 'cost_price', 'preço custo', 'preço de custo'],
        'moeda': ['moeda', 'currency', 'moe'],
        'estoque': ['estoque', 'stock', 'current_stock', 'qtd', 'quantidade', 'estoque atual'],
        'estoque_minimo': ['estoque_minimo', 'minimum_stock', 'min_stock', 'estoque min', 'estoque mínimo'],
        'armazem': ['armazem', 'warehouse', 'warehouse_code', 'local', 'armazém', 'codigo armazem'],
        'ncm': ['ncm', 'codigo_ncm', 'ncm_code'],
        'ipi': ['ipi', 'ipi_percentage', 'percentual_ipi', '% ipi', 'perc ipi', 'aliq ipi', 'aliq_ipi'],
        'icms': ['icms', 'icms_percentage', 'percentual_icms', '% icms', 'perc icms', 'aliq icms', 'aliq_icms', 'icms?'],
        'icms_base': ['icms_base', 'base_icms', 'base calc icms', 'base_calc_icms', 'base calculo icms'],
        'origem': ['origem', 'origin', 'produto_origem'],
        'quantidade': ['quantidade', 'quant', 'qtd', 'qty', 'quantity'],
        'valor_unitario': ['valor_unitario', 'valor unitario', 'valor unit', 'unit_value', 'preco_unitario', 'preço unitário'],
        'desconto': ['desconto', 'discount', 'desc', 'desconto?'],
        'fornecedor_codigo': ['fornecedor_codigo', 'cod_fornecedor', 'supplier_code', 'código fornecedor', 'codigo fornecedor'],
        'fornecedor_nome': ['fornecedor_nome', 'fornecedor', 'supplier', 'supplier_name', 'nome fornecedor'],
        'codigo_barras': ['codigo_barras', 'barcode', 'ean', 'código de barras', 'codigo de barras'],
        'peso': ['peso', 'weight', 'peso_kg'],
        'peso_unidade': ['peso_unidade', 'weight_unit', 'un_peso', 'unidade peso'],
        'ativo': ['ativo', 'active', 'status'],
        'observacoes': ['observacoes', 'obs', 'observations', 'observações', 'observacao', 'notas'],
    }

    def __init__(self, file_path: str, sheet_name: str = None):
        self.file_path = file_path
        self.sheet_name = sheet_name
        self.df = None
        self.column_map = {}

    def parse(self) -> List[Dict[str, Any]]:
        try:
            if self.sheet_name:
                self.df = pd.read_excel(self.file_path, sheet_name=self.sheet_name)
            else:
                self.df = pd.read_excel(self.file_path)

            # Check if first row contains headers (if columns are "Unnamed: X")
            if all('unnamed' in str(col).lower() for col in self.df.columns):
                # Use first row as headers
                self.df.columns = self.df.iloc[0]
                self.df = self.df[1:].reset_index(drop=True)

            self.df.columns = self.df.columns.str.strip().str.lower()

            self._map_columns()

            products = []
            for idx, row in self.df.iterrows():
                try:
                    product_data = self._extract_product_data(row)
                    if product_data.get('product_code'):
                        # If description is missing, use product_code as description
                        if not product_data.get('description'):
                            product_data['description'] = f"Produto {product_data['product_code']}"
                        products.append(product_data)
                    else:
                        logger.warning(f"Linha {idx + 2} ignorada: falta código")
                except Exception as e:
                    logger.error(f"Erro ao processar linha {idx + 2}: {str(e)}")
                    continue

            logger.info(f"Total de {len(products)} produtos extraídos do Excel")
            return products

        except Exception as e:
            logger.error(f"Erro ao analisar arquivo Excel: {str(e)}")
            raise

    def _map_columns(self):
        df_columns = set(self.df.columns)

        for field_name, possible_names in self.COLUMN_MAPPING.items():
            for possible_name in possible_names:
                if possible_name in df_columns:
                    self.column_map[field_name] = possible_name
                    break

    def _get_column_value(self, row, field_name: str, default=None):
        if field_name in self.column_map:
            column_name = self.column_map[field_name]
            value = row.get(column_name, default)
            if pd.isna(value):
                return default
            return value
        return default

    def _extract_product_data(self, row) -> Dict[str, Any]:
        product_data = {
            'product_code': str(self._get_column_value(row, 'codigo', '')).strip(),
            'description': str(self._get_column_value(row, 'descricao', '')).strip(),
            'short_description': str(self._get_column_value(row, 'descricao_curta', '')).strip() or None,
            'product_type': str(self._get_column_value(row, 'tipo', '')).strip() or None,
            'product_group': str(self._get_column_value(row, 'grupo', '')).strip() or None,
            'product_category': str(self._get_column_value(row, 'categoria', '')).strip() or None,
            'unit_of_measure': str(self._get_column_value(row, 'unidade', '')).strip() or None,
            'second_unit': str(self._get_column_value(row, 'segunda_unidade', '')).strip() or None,
            'conversion_factor': self._parse_decimal(self._get_column_value(row, 'fator_conversao')),
            'sale_price': self._parse_decimal(self._get_column_value(row, 'preco_venda')),
            'cost_price': self._parse_decimal(self._get_column_value(row, 'preco_custo')),
            'currency': str(self._get_column_value(row, 'moeda', 'BRL')).strip(),
            'current_stock': self._parse_decimal(self._get_column_value(row, 'estoque', 0)),
            'minimum_stock': self._parse_decimal(self._get_column_value(row, 'estoque_minimo')),
            'warehouse_code': str(self._get_column_value(row, 'armazem', '')).strip() or None,
            'ncm_code': str(self._get_column_value(row, 'ncm', '')).strip() or None,
            'ipi_percentage': self._parse_decimal(self._get_column_value(row, 'ipi')),
            'icms_percentage': self._parse_decimal(self._get_column_value(row, 'icms')),
            'icms_base': self._parse_decimal(self._get_column_value(row, 'icms_base')),
            'origin': str(self._get_column_value(row, 'origem', '')).strip() or None,
            'quantity': self._parse_decimal(self._get_column_value(row, 'quantidade')),
            'unit_value': self._parse_decimal(self._get_column_value(row, 'valor_unitario')),
            'discount': self._parse_decimal(self._get_column_value(row, 'desconto')),
            'supplier_code': str(self._get_column_value(row, 'fornecedor_codigo', '')).strip() or None,
            'supplier_name': str(self._get_column_value(row, 'fornecedor_nome', '')).strip() or None,
            'barcode': str(self._get_column_value(row, 'codigo_barras', '')).strip() or None,
            'weight': self._parse_decimal(self._get_column_value(row, 'peso')),
            'weight_unit': str(self._get_column_value(row, 'peso_unidade', 'KG')).strip(),
            'active': self._parse_boolean(self._get_column_value(row, 'ativo', True)),
            'observations': str(self._get_column_value(row, 'observacoes', '')).strip() or None,
        }

        # Convert row to dict and clean pandas data types for JSON serialization
        raw_dict = row.to_dict()
        clean_raw_data = {}
        for key, value in raw_dict.items():
            if pd.isna(value):
                clean_raw_data[key] = None
            elif isinstance(value, (pd.Timestamp, pd.Timedelta)):
                clean_raw_data[key] = str(value)
            elif hasattr(value, 'item'):  # numpy types
                clean_raw_data[key] = value.item()
            else:
                clean_raw_data[key] = value

        product_data['raw_data'] = clean_raw_data

        return product_data

    def _parse_decimal(self, value, default=None) -> Decimal:
        if value is None or pd.isna(value):
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
        if value is None or pd.isna(value):
            return default

        if isinstance(value, bool):
            return value

        if isinstance(value, (int, float)):
            return value != 0

        if isinstance(value, str):
            value = value.strip().lower()
            if value in ['true', 'sim', 's', 'yes', 'y', '1', 'ativo']:
                return True
            elif value in ['false', 'nao', 'não', 'n', 'no', '0', 'inativo']:
                return False

        return default

    def get_sheet_names(self) -> List[str]:
        try:
            excel_file = pd.ExcelFile(self.file_path)
            return excel_file.sheet_names
        except Exception as e:
            logger.error(f"Erro ao obter nomes das planilhas: {str(e)}")
            return []
