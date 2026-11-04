@echo off
REM Inspector C5 - baixa e abre sempre o HTML mais recente do GitHub.
setlocal

set "URL_HTML=https://raw.githubusercontent.com/luanmanini-im/c5-inspector/main/index.html"
set "PASTA_DESTINO=%~dp0Front"
set "ARQUIVO_HTML=%PASTA_DESTINO%\Q.A.html"
set "ARQUIVO_TEMP=%TEMP%\Inspector_QA_%RANDOM%.html"
set "URL_SERVICO=https://raw.githubusercontent.com/luanmanini-im/c5-inspector/main/ConsultaApiLocal.py"
set "ARQUIVO_SERVICO=%~dp0ConsultaApiLocal.py"
set "SERVICO_TEMP=%TEMP%\Inspector_Consulta_%RANDOM%.py"
set "PYTHON=py -3"
py -3 --version >nul 2>&1
if errorlevel 1 (
    set "PYTHON=python"
    python --version >nul 2>&1
    if errorlevel 1 (
        echo Instale Python 3.9 ou superior com a opcao Add Python to PATH e tente novamente.
        pause
        exit /b 1
    )
)

if not exist "%PASTA_DESTINO%\" mkdir "%PASTA_DESTINO%"
if errorlevel 1 (
    echo.
    echo Nao foi possivel criar a pasta de destino: "%PASTA_DESTINO%"
    pause
    exit /b 1
)

echo Baixando o servico de consultas local...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { Invoke-WebRequest -Uri $env:URL_SERVICO -OutFile $env:SERVICO_TEMP -UseBasicParsing; $conteudo = Get-Content -LiteralPath $env:SERVICO_TEMP -Raw; if ($conteudo -notmatch 'class ConsultaLocal:' -or $conteudo -notmatch 'def criar_servidor') { throw 'Servico local invalido.' }; Move-Item -LiteralPath $env:SERVICO_TEMP -Destination $env:ARQUIVO_SERVICO -Force } catch { Write-Host ('Erro ao atualizar servico: ' + $_.Exception.Message); exit 1 }"
if errorlevel 1 (
    del "%SERVICO_TEMP%" >nul 2>&1
    pause
    exit /b 1
)

echo Baixando a versao mais recente do Inspector...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; try { Invoke-WebRequest -Uri $env:URL_HTML -OutFile $env:ARQUIVO_TEMP -UseBasicParsing -ErrorAction Stop; $html = Get-Content -LiteralPath $env:ARQUIVO_TEMP -Raw -ErrorAction Stop; if ($html.Length -lt 10000 -or $html -notmatch '(?is)<!doctype\s+html' -or $html -notmatch '(?is)<title>\s*Inspector\s*-') { throw 'O arquivo baixado nao parece ser um HTML valido do Inspector.' }; Move-Item -LiteralPath $env:ARQUIVO_TEMP -Destination $env:ARQUIVO_HTML -Force -ErrorAction Stop } catch { Write-Host ('Erro ao baixar ou validar o HTML: ' + $_.Exception.Message); exit 1 }"
if errorlevel 1 (
    echo.
    echo Falha ao atualizar o HTML. O arquivo local anterior foi preservado.
    del "%ARQUIVO_TEMP%" >nul 2>&1
    pause
    exit /b 1
)

echo Iniciando o Inspector C5...
%PYTHON% "%ARQUIVO_SERVICO%" --html "%ARQUIVO_HTML%"
if errorlevel 1 (
    echo O servico local foi encerrado com erro. Confira a mensagem acima.
    pause
    exit /b 1
)
exit /b 0
