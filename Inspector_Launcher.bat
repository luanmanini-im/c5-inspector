@echo off
REM ==========================================
REM Inspector C5 - Launcher com auto-atualizacao
REM ==========================================
REM Baixa sempre a versao mais recente do pacote Front (Q.A.html + Iniciar_Inspector.bat +
REM extensao de proxy) direto do GitHub e ja abre o Chrome configurado. Nao faz checagem de
REM versao (sempre baixa/extrai de novo) - simples e sem risco de ficar desatualizado.
REM
setlocal
set "URL_ZIP=https://raw.githubusercontent.com/luanmanini-im/c5-inspector/main/Front.zip"
set "PASTA_DESTINO=%~dp0Front"
set "ZIP_TEMP=%TEMP%\Inspector_Front_%RANDOM%.zip"

echo Baixando a versao mais recente do Inspector...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Invoke-WebRequest -Uri '%URL_ZIP%' -OutFile '%ZIP_TEMP%' -UseBasicParsing -ErrorAction Stop } catch { Write-Host ('Erro ao baixar: ' + $_.Exception.Message); exit 1 }"
if errorlevel 1 (
    echo.
    echo Falha ao baixar o pacote. Verifique sua conexao com a internet e tente novamente.
    pause
    exit /b 1
)

echo Extraindo arquivos...
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Expand-Archive -Path '%ZIP_TEMP%' -DestinationPath '%PASTA_DESTINO%' -Force -ErrorAction Stop } catch { Write-Host ('Erro ao extrair: ' + $_.Exception.Message); exit 1 }"
if errorlevel 1 (
    echo.
    echo Falha ao extrair o pacote baixado.
    del "%ZIP_TEMP%" >nul 2>&1
    pause
    exit /b 1
)
del "%ZIP_TEMP%" >nul 2>&1

REM Busca o Q.A.html recursivamente dentro da pasta extraida - resiliente ao caso do
REM Front.zip ter sido compactado com uma pasta "Front" por dentro (arquivos ficam em
REM ...\Front\Front\Q.A.html em vez de ...\Front\Q.A.html).
set "ARQUIVO_HTML="
for /f "usebackq delims=" %%F in (`powershell -NoProfile -Command "(Get-ChildItem -Path '%PASTA_DESTINO%' -Filter 'Q.A.html' -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName)"`) do set "ARQUIVO_HTML=%%F"

if "%ARQUIVO_HTML%"=="" (
    echo.
    echo Nao foi possivel localizar o Q.A.html dentro do pacote extraido.
    pause
    exit /b 1
)

echo Iniciando o Inspector C5...
start "" chrome.exe --disable-web-security --user-data-dir="C:\ChromeDev" "%ARQUIVO_HTML%"
exit
