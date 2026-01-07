# 1. IMAGEM BASE
FROM python:3.13-slim

# 2. INSTALA DEPENDÊNCIAS NATIVAS E FERRAMENTAS
# Instala curl, gnupg e unixodbc-dev
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    dirmngr \
    unixodbc-dev \
    # Limpa o cache para reduzir o tamanho 
    && rm -rf /var/lib/apt/lists/*

# 3. ADICIONA CHAVE GPG DA MICROSOFT
# Adiciona a chave GPG da Microsoft e armazena no local que usaremos no sources.list.d
RUN curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /etc/apt/keyrings/microsoft.gpg

# 4. ADICIONA REPOSITÓRIO ODBC COM ASSINATURA EXPLÍCITA
# Usamos o caminho da chave no comando 'signed-by'
RUN echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/debian/12/prod bookworm main" > /etc/apt/sources.list.d/mssql-release.list

# 5. INSTALAÇÃO DO DRIVER ODBC
# Atualiza os repositórios novamente e instala o driver
RUN apt-get update \
    && ACCEPT_EULA=Y apt-get install -y msodbcsql17 mssql-tools \
    # Limpa o cache após a instalação
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# 6. CONFIGURAÇÃO DO DRIVER UNIXODBC
# Verifica e configura o caminho correto do driver
RUN odbcinst -q -d -n "ODBC Driver 17 for SQL Server" || \
    (echo '[ODBC Driver 17 for SQL Server]' >> /etc/odbcinst.ini && \
     echo 'Description=Microsoft ODBC Driver 17 for SQL Server' >> /etc/odbcinst.ini && \
     echo 'Driver=/opt/microsoft/msodbcsql17/lib64/libmsodbcsql-17.so' >> /etc/odbcinst.ini && \
     echo 'UsageCount=1' >> /etc/odbcinst.ini)

# Adiciona ao PATH e LD_LIBRARY_PATH
ENV PATH="/opt/mssql-tools/bin:${PATH}"
ENV LD_LIBRARY_PATH="/opt/microsoft/msodbcsql17/lib64:${LD_LIBRARY_PATH}"

# 7. CONFIGURAÇÃO PYTHON
WORKDIR /app

# Copia e instala as dependências Python
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

# 8. COPIA O CÓDIGO RESTANTE
COPY . /app/

# 9. COMANDO DE INICIALIZAÇÃO
CMD sh -c "python manage.py collectstatic --noinput && python manage.py migrate --noinput && PYTHONPATH=/app gunicorn --chdir /app portalweb.wsgi:application -w 2 -t 30 -b 0.0.0.0:3000 --log-level debug --log-syslog"