from django import forms
from .models import FileUpload


class FileUploadForm(forms.Form):
    FILE_TYPE_CHOICES = [
        ('EXCEL', 'Excel (.xlsx, .xls)'),
        ('XML', 'XML (.xml)'),
    ]

    file = forms.FileField(
        label='Arquivo',
        help_text='Selecione um arquivo Excel ou XML com os dados dos produtos',
        widget=forms.FileInput(attrs={
            'class': 'form-control',
            'accept': '.xlsx,.xls,.xml'
        })
    )

    file_type = forms.ChoiceField(
        label='Tipo de Arquivo',
        choices=FILE_TYPE_CHOICES,
        widget=forms.RadioSelect(attrs={
            'class': 'form-check-input'
        })
    )

    def clean_file(self):
        file = self.cleaned_data.get('file')

        if not file:
            raise forms.ValidationError('Por favor, selecione um arquivo.')

        file_extension = file.name.split('.')[-1].lower()
        valid_extensions = ['xlsx', 'xls', 'xml']

        if file_extension not in valid_extensions:
            raise forms.ValidationError(
                f'Tipo de arquivo não suportado. Use: {", ".join(valid_extensions)}'
            )

        max_size = 10 * 1024 * 1024
        if file.size > max_size:
            raise forms.ValidationError(
                f'O arquivo é muito grande. Tamanho máximo: 10MB'
            )

        return file

    def clean(self):
        cleaned_data = super().clean()
        file = cleaned_data.get('file')
        file_type = cleaned_data.get('file_type')

        if file and file_type:
            file_extension = file.name.split('.')[-1].lower()

            if file_type == 'EXCEL' and file_extension not in ['xlsx', 'xls']:
                raise forms.ValidationError(
                    'O tipo de arquivo selecionado não corresponde ao arquivo enviado.'
                )

            if file_type == 'XML' and file_extension != 'xml':
                raise forms.ValidationError(
                    'O tipo de arquivo selecionado não corresponde ao arquivo enviado.'
                )

        return cleaned_data
