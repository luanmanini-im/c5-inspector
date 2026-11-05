#!/bin/sh
# Inspector C5 - instalacao unica e atualizacao automatica no Linux.
if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' 'Instale Python 3.9 ou superior e execute novamente pelo terminal.'
    exit 1
fi

exec python3 -c '
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

URL_BASE = "https://raw.githubusercontent.com/luanmanini-im/c5-inspector/main/"


def pasta_desktop():
    if shutil.which("xdg-user-dir"):
        resultado = subprocess.run(
            ["xdg-user-dir", "DESKTOP"], check=True, capture_output=True, text=True
        )
        desktop = Path(resultado.stdout.strip())
        if not desktop.is_absolute():
            raise ValueError("xdg-user-dir retornou uma pasta de trabalho invalida.")
        return desktop
    print("xdg-user-dir nao encontrado; usando a pasta Desktop do usuario.")
    return Path.home() / "Desktop"


def atualizar(instalacao):
    front = instalacao / "Front"
    front.mkdir(exist_ok=True)
    # Valida ambos os downloads antes de substituir os arquivos em uso.
    with tempfile.TemporaryDirectory(prefix=".download-", dir=instalacao) as temporaria:
        staging = Path(temporaria)
        for nome in ("ConsultaApiLocal.py", "index.html"):
            print("Baixando " + nome + "...")
            with urllib.request.urlopen(URL_BASE + nome, timeout=60) as resposta:
                (staging / nome).write_bytes(resposta.read())
        servico = (staging / "ConsultaApiLocal.py").read_text(encoding="utf-8")
        if "class ConsultaLocal:" not in servico or "def criar_servidor" not in servico:
            raise ValueError("Servico local invalido. Arquivos anteriores preservados.")
        html = (staging / "index.html").read_text(encoding="utf-8")
        if (len(html) < 10000 or not re.search(r"<!doctype\s+html", html, re.I)
                or not re.search(r"<title>\s*Inspector\s*-", html, re.I)):
            raise ValueError("HTML do Inspector invalido. Arquivos anteriores preservados.")
        (staging / "ConsultaApiLocal.py").replace(instalacao / "ConsultaApiLocal.py")
        (staging / "index.html").replace(front / "Q.A.html")


def main():
    if sys.version_info < (3, 9):
        raise ValueError("Instale Python 3.9 ou superior.")
    instalacao = pasta_desktop() / "Inspector"
    origem = Path(sys.argv[1]).resolve()
    launcher = instalacao / "Inspector_Launcher.sh"
    if origem != launcher.resolve():
        print("Inspector C5 - Instalacao\n\nPasta padrao: " + str(instalacao))
        print("O launcher, a tela e o servico local ficarao nesta pasta.")
        print("Se ja existir uma instalacao, ela sera atualizada.")
        resposta = input("Deseja continuar? [s/N] ").strip().lower()
        if resposta not in ("s", "sim"):
            print("Instalacao cancelada. Nenhum arquivo foi alterado.")
            return 0
        instalacao.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(origem, launcher)
        launcher.chmod(launcher.stat().st_mode | 0o100)
        print("Launcher copiado. O arquivo baixado pode ser apagado: " + str(origem))
    atualizar(instalacao)
    print("Iniciando Inspector. Mantenha este terminal aberto; Ctrl+C encerra o servico.")
    resultado = subprocess.call(
        [sys.executable, str(instalacao / "ConsultaApiLocal.py"),
         "--html", str(instalacao / "Front" / "Q.A.html")],
        cwd=instalacao,
    )
    if resultado:
        print("O servico local foi encerrado com erro. Confira a mensagem acima.", file=sys.stderr)
    return resultado


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nInspector encerrado.")
        sys.exit(130)
    except (OSError, ValueError, EOFError, urllib.error.URLError, subprocess.CalledProcessError) as erro:
        print("Erro no launcher: " + str(erro), file=sys.stderr)
        sys.exit(1)
' "$0"
