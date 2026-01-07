import os
import uuid
from datetime import datetime
from typing import Dict, List, Any
import logging

from django.db import transaction
from django.core.files.uploadedfile import UploadedFile

from Main.models import FileUpload, ProductBatch, Product
from .excel_parser import ExcelParser
from .xml_parser import XMLParser

logger = logging.getLogger(__name__)


class FileProcessor:

    def __init__(self, file_upload: FileUpload):
        self.file_upload = file_upload

    def process(self) -> Dict[str, Any]:
        try:
            self.file_upload.status = 'PROCESSING'
            self.file_upload.save()

            file_path = self.file_upload.file.path
            file_type = self.file_upload.file_type

            products_data = []

            if file_type == 'EXCEL':
                products_data = self._process_excel(file_path)
            elif file_type == 'XML':
                products_data = self._process_xml(file_path)
            else:
                raise ValueError(f"Tipo de arquivo não suportado: {file_type}")

            if not products_data:
                raise ValueError("Nenhum produto encontrado no arquivo")

            result = self._save_products(products_data)

            self.file_upload.status = 'COMPLETED'
            self.file_upload.total_records = result['total']
            self.file_upload.processed_records = result['saved']
            self.file_upload.save()

            logger.info(f"Processamento concluído: {result['saved']} de {result['total']} produtos salvos")

            return {
                'success': True,
                'message': f"Processamento concluído com sucesso",
                'total': result['total'],
                'saved': result['saved'],
                'errors': result['errors'],
                'batch_code': result['batch_code']
            }

        except Exception as e:
            self.file_upload.status = 'FAILED'
            self.file_upload.error_message = str(e)
            self.file_upload.save()

            logger.error(f"Erro ao processar arquivo: {str(e)}")

            return {
                'success': False,
                'message': f"Erro ao processar arquivo: {str(e)}",
                'total': 0,
                'saved': 0,
                'errors': [str(e)]
            }

    def _process_excel(self, file_path: str) -> List[Dict[str, Any]]:
        logger.info(f"Processando arquivo Excel: {file_path}")
        parser = ExcelParser(file_path)
        products = parser.parse()
        return products

    def _process_xml(self, file_path: str) -> List[Dict[str, Any]]:
        logger.info(f"Processando arquivo XML: {file_path}")
        parser = XMLParser(file_path)
        products = parser.parse()
        return products

    def _save_products(self, products_data: List[Dict[str, Any]]) -> Dict[str, Any]:
        # Check if this file upload already has a batch
        try:
            existing_batch = ProductBatch.objects.get(file_upload=self.file_upload)
            logger.warning(f"FileUpload {self.file_upload.id} já possui um lote: {existing_batch.batch_code}")
            return {
                'total': len(products_data),
                'saved': 0,
                'errors': ['Este arquivo já foi processado anteriormente'],
                'batch_code': existing_batch.batch_code,
                'batch': existing_batch
            }
        except ProductBatch.DoesNotExist:
            pass  # No existing batch, proceed normally

        batch_code = self._generate_batch_code()

        # Create ProductBatch first (outside of product-saving transaction)
        # This ensures the batch exists even if product saving fails
        batch = ProductBatch.objects.create(
            file_upload=self.file_upload,
            batch_code=batch_code
        )

        saved_count = 0
        errors = []

        # Save products within a transaction
        # If products fail to save, the batch still exists
        try:
            with transaction.atomic():
                for idx, product_data in enumerate(products_data):
                    try:
                        # Make a copy to avoid modifying the original dict
                        product_dict = product_data.copy()
                        raw_data = product_dict.pop('raw_data', None)

                        product = Product.objects.create(
                            batch=batch,
                            raw_data=raw_data,
                            **product_dict
                        )
                        saved_count += 1
                        logger.debug(f"Produto salvo: {product.product_code}")

                    except Exception as e:
                        error_msg = f"Erro ao salvar produto {idx + 1} ({product_dict.get('product_code', 'N/A')}): {str(e)}"
                        logger.error(error_msg)
                        errors.append(error_msg)
                        # Continue processing other products even if one fails
        except Exception as e:
            logger.error(f"Erro crítico ao salvar produtos: {str(e)}")
            errors.append(f"Erro crítico: {str(e)}")

        logger.info(f"Lote {batch_code}: {saved_count} produtos salvos de {len(products_data)}")

        return {
            'total': len(products_data),
            'saved': saved_count,
            'errors': errors,
            'batch_code': batch_code,
            'batch': batch
        }

    def _generate_batch_code(self) -> str:
        timestamp = datetime.now().strftime('%Y%m%d%H%M%S')
        unique_id = str(uuid.uuid4())[:8]
        return f"BATCH-{timestamp}-{unique_id}"


def process_uploaded_file(uploaded_file: UploadedFile, file_type: str, user=None) -> Dict[str, Any]:
    try:
        file_upload = FileUpload.objects.create(
            file=uploaded_file,
            file_type=file_type,
            uploaded_by=user,
            status='PENDING'
        )

        processor = FileProcessor(file_upload)
        result = processor.process()

        return result

    except Exception as e:
        logger.error(f"Erro ao processar upload: {str(e)}")
        return {
            'success': False,
            'message': f"Erro ao processar upload: {str(e)}",
            'total': 0,
            'saved': 0,
            'errors': [str(e)]
        }
