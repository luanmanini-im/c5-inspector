@echo off
REM Atualiza o HTML local diretamente do repositorio antes de iniciar o Inspector.
setlocal

set "URL_HTML=https://raw.githubusercontent.com/luanmanini-im/c5-inspector/main/index.html"
set "ARQUIVO_HTML=%~dp0Q.A.html"
set "ARQUIVO_TEMP=%TEMP%\Inspector_QA_%RANDOM%.html"

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
start "" chrome.exe --disable-web-security --user-data-dir="C:\ChromeDev" "%ARQUIVO_HTML%"
exit /b 0
