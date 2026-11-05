@echo off
REM Inspector C5 - instala tudo em uma pasta padrao unica e abre sempre a versao mais recente.
setlocal EnableExtensions

REM ============================================================
REM 1) Resolve a pasta padrao de instalacao: Area de Trabalho\Inspector
REM    (usa o PowerShell para suportar Area de Trabalho no OneDrive)
REM ============================================================
set "DESKTOP="
for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "[Environment]::GetFolderPath('Desktop')"`) do set "DESKTOP=%%D"
if not defined DESKTOP set "DESKTOP=%USERPROFILE%\Desktop"

set "PASTA_INSTALACAO=%DESKTOP%\Inspector"
set "LAUNCHER_DESTINO=%PASTA_INSTALACAO%\Inspector_Launcher.bat"

REM Se ja estiver rodando da pasta padrao, pula direto para a execucao.
if /i "%~dp0"=="%PASTA_INSTALACAO%\" goto :executar

REM ============================================================
REM 2) Primeira execucao (ou launcher baixado em outra pasta):
REM    pede confirmacao e instala tudo na pasta padrao.
REM ============================================================
echo ============================================================
echo  Inspector C5 - Instalacao
echo ============================================================
echo.
echo O Inspector sera instalado na pasta padrao:
echo.
echo   %PASTA_INSTALACAO%
echo.
echo Todos os arquivos (launcher, tela e servico local) ficarao
echo concentrados nessa pasta. Nas proximas vezes, abra o
echo Inspector pelo atalho dentro dela.
echo.
choice /c SN /m "Deseja continuar? [S]im / [N]ao"
if errorlevel 2 goto :cancelado

mkdir "%PASTA_INSTALACAO%" 2>nul
if not exist "%PASTA_INSTALACAO%\" (
    echo.
    echo Nao foi possivel criar a pasta: "%PASTA_INSTALACAO%"
    pause
    exit /b 1
)

copy /y "%~f0" "%LAUNCHER_DESTINO%" >nul
if errorlevel 1 (
    echo.
    echo Nao foi possivel copiar o launcher para: "%LAUNCHER_DESTINO%"
    pause
    exit /b 1
)

echo.
echo Instalado com sucesso em: %PASTA_INSTALACAO%
echo Voce ja pode apagar este arquivo baixado: "%~f0"
echo Iniciando o Inspector a partir da pasta padrao...
start "Inspector C5" /d "%PASTA_INSTALACAO%" cmd /c ""%LAUNCHER_DESTINO%""
exit /b 0

:cancelado
echo.
echo Instalacao cancelada pelo usuario.
pause
exit /b 0

REM ============================================================
REM 3) Execucao a partir da pasta padrao: baixa/atualiza e abre.
REM ============================================================
:executar
set "URL_HTML=https://raw.githubusercontent.com/luanmanini-im/c5-inspector/main/index.html"
set "PASTA_DESTINO=%PASTA_INSTALACAO%\Front"
set "ARQUIVO_HTML=%PASTA_DESTINO%\Q.A.html"
set "ARQUIVO_TEMP=%TEMP%\Inspector_QA_%RANDOM%.html"
set "URL_SERVICO=https://raw.githubusercontent.com/luanmanini-im/c5-inspector/main/ConsultaApiLocal.py"
set "ARQUIVO_SERVICO=%PASTA_INSTALACAO%\ConsultaApiLocal.py"
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

mkdir "%PASTA_DESTINO%" 2>nul
if not exist "%PASTA_DESTINO%\" (
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
