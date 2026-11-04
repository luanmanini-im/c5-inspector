"""Ponte local do Inspector. Credenciais ficam somente na memoria deste processo."""

import argparse
import hashlib
import hmac
import json
import os
import re
import secrets
import shutil
import subprocess
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


API_URL = "https://consultatributos.com.br:8443/api/v3/public/SaneamentoGrades"
UFS = set("AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO".split())


def validar_payload(dados):
    esquema = {
        "emit": {"amb": "numero", "cnpj": "cnpj", "crt": "numero", "regimeTrib": "texto",
                 "regimeEspecial": "opcional", "uf": "uf", "cnae": "texto", "substICMS": "sn", "interdependente": "sn"},
        "perfil": {"uf": "ufs", "cfop": "cfop", "caracTrib": "numeros", "finalidade": "numero",
                   "simplesN": "sn", "origem": "origem", "substICMS": "sn", "prodZFM": "sn"},
    }
    if not isinstance(dados, dict):
        raise ValueError("Informe emitente e perfil tributario.")
    resultado = {}
    for grupo, campos in esquema.items():
        entrada = dados.get(grupo)
        if not isinstance(entrada, dict):
            raise ValueError("Grupo invalido: " + grupo)
        resultado[grupo] = {}
        for campo, tipo in campos.items():
            valor = entrada.get(campo)
            numero = lambda v: type(v) is int and v >= 0
            valido = False
            if tipo == "numero":
                valido = numero(valor)
            elif tipo in ("texto", "opcional"):
                valido = isinstance(valor, str) and len(valor) <= 128 and (tipo == "opcional" or bool(valor.strip()))
            elif tipo in ("cnpj", "cfop", "origem"):
                padrao = {"cnpj": r"\d{14}", "cfop": r"\d{4}", "origem": r"[0-8]"}[tipo]
                valido = isinstance(valor, str) and bool(re.fullmatch(padrao, valor, flags=re.ASCII))
            elif tipo == "sn":
                valido = isinstance(valor, str) and valor in ("S", "N")
            elif tipo == "uf":
                valido = isinstance(valor, str) and valor in UFS
            elif tipo == "ufs":
                valido = isinstance(valor, list) and 1 <= len(valor) <= 27 and all(isinstance(v, str) and v in UFS for v in valor)
            elif tipo == "numeros":
                valido = isinstance(valor, list) and 1 <= len(valor) <= 50 and all(numero(v) for v in valor)
            if not valido:
                raise ValueError("Campo invalido: " + grupo + "." + campo)
            resultado[grupo][campo] = valor
    if resultado["emit"]["amb"] not in (1, 2) or resultado["emit"]["crt"] not in (1, 2, 3, 4):
        raise ValueError("Ambiente ou CRT invalido.")
    return resultado


def post_json(url, dados, headers=None, timeout=30):
    request = urllib.request.Request(
        url, data=json.dumps(dados).encode("utf-8"),
        headers={"Content-Type": "text/plain;charset=utf-8", **(headers or {})}, method="POST",
    )
    class SemRedirecionamento(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, response_headers, newurl):
            return None

    abrir = urllib.request.build_opener(SemRedirecionamento()).open if url == API_URL else urllib.request.urlopen
    try:
        with abrir(request, timeout=timeout) as response:
            return json.load(response)
    except urllib.error.HTTPError as error:
        error.close()
        raise


class ConsultaLocal:
    def __init__(self, gas_url, transport=post_json, clock=time.monotonic, sleep=time.sleep):
        self.gas_url = gas_url
        self.transport = transport
        self.clock = clock
        self.sleep = sleep
        self.cache = {}
        self.cache_lock = threading.Lock()
        self.rate_lock = threading.Lock()
        self.next_send = 0
        self.blocked_until = 0
        self.workers = threading.BoundedSemaphore(20)

    def credenciais(self, auth_token):
        if not isinstance(auth_token, str) or not auth_token or len(auth_token) > 256:
            raise ValueError("Sessao ausente ou invalida.")
        chave = hashlib.sha256(auth_token.encode()).hexdigest()
        with self.cache_lock:
            agora = self.clock()
            self.cache = {k: v for k, v in self.cache.items() if v[0] > agora}
            salvo = self.cache.get(chave)
            if salvo:
                return salvo[1]
            config = self.transport(self.gas_url, {"action": "consulta_api_credenciais_local", "authToken": auth_token})
            if not isinstance(config, dict):
                raise ValueError("Resposta invalida ao buscar credenciais no Google.")
            if config.get("sucesso") is not True:
                raise ValueError(config.get("erro", "Falha na autenticacao com Google.") + " " + config.get("detalhes", ""))
            if not isinstance(config.get("login"), str) or not re.fullmatch(r"[0-9]{14}", config["login"]) or not config.get("senha"):
                raise ValueError("Credenciais da API nao configuradas na planilha.")
            credenciais = {"login": config["login"], "senha": config["senha"]}
            self.cache[chave] = (self.clock() + 300, credenciais)
            return credenciais

    def aguardar_envio(self):
        with self.rate_lock:
            if self.blocked_until > self.clock():
                raise ValueError("API limitou as consultas. Aguarde um minuto antes de retomar.")
            espera = self.next_send - self.clock()
            if espera > 0:
                self.sleep(espera)
            self.next_send = self.clock() + 0.06

    def consultar(self, params):
        base = validar_payload(params.get("payload"))
        itens = params.get("itens")
        if not isinstance(itens, list) or len(itens) != 1:
            raise ValueError("Envie um item por chamada local.")
        item = itens[0]
        if not isinstance(item, dict) or item.get("tipo") not in ("EAN", "SKU") or not isinstance(item.get("codigo"), str):
            raise ValueError("Informe tipo EAN/SKU e codigo em texto.")
        codigo = item["codigo"].strip()
        if not codigo or len(codigo) > 128:
            raise ValueError("Codigo invalido.")
        credenciais = self.credenciais(params.get("authToken"))
        base["produtos"] = [{"ncm": "", "codigo": codigo, "descricao": "", "codImendes": "",
                             "codInterno": "S" if item["tipo"] == "SKU" else "N"}]
        with self.workers:
            self.aguardar_envio()
            try:
                dados = self.transport(API_URL, base, {"Content-Type": "application/json", **credenciais})
            except urllib.error.HTTPError as error:
                error.close()
                if error.code == 429:
                    with self.rate_lock:
                        self.blocked_until = self.clock() + 60
                if error.code in (401, 403):
                    with self.cache_lock:
                        self.cache.clear()
                return {"sucesso": False, "erro": "API de consulta: HTTP " + str(error.code), "statusCode": error.code}
        if not isinstance(dados, dict) or not isinstance(dados.get("Grupos"), list):
            raise ValueError("Resposta da API sem lista Grupos. Consulta nao confirmada.")
        return {"sucesso": True, "resultados": [{"tipo": item["tipo"], "codigo": codigo, "dados_api": dados}]}


def criar_servidor(consulta, token):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass  # Nao registrar tokens, payloads ou credenciais no console HTTP.

        def responder(self, status, dados):
            conteudo = json.dumps(dados, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(conteudo)))
            self.end_headers()
            self.wfile.write(conteudo)

        def do_POST(self):
            self.connection.settimeout(35)
            if not hmac.compare_digest(self.headers.get("X-Inspector-Local", "").encode("utf-8"), token.encode("ascii")):
                return self.responder(403, {"sucesso": False, "erro": "Launcher local nao autorizado."})
            if self.path not in ("/status", "/consultar", "/limpar"):
                return self.responder(404, {"sucesso": False, "erro": "Rota local inexistente."})
            try:
                tamanho = int(self.headers.get("Content-Length", "0"))
                if tamanho < 2 or tamanho > 65536:
                    raise ValueError("Corpo da requisicao invalido.")
                params = json.loads(self.rfile.read(tamanho))
                if not isinstance(params, dict):
                    raise ValueError("Requisicao deve conter objeto JSON.")
                if self.path == "/status":
                    return self.responder(200, {"sucesso": True, "servico": "Inspector Consulta API", "taxaLocal": 1000})
                if self.path == "/limpar":
                    with consulta.cache_lock:
                        consulta.cache.clear()
                    return self.responder(200, {"sucesso": True})
                self.responder(200, consulta.consultar(params))
            except (ValueError, KeyError) as error:
                self.responder(400, {"sucesso": False, "erro": str(error)})
            except (urllib.error.URLError, TimeoutError, OSError):
                self.responder(502, {"sucesso": False, "erro": "Falha de rede/TLS ou timeout. Verifique VPN, certificado e conexao."})

    servidor = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    servidor.daemon_threads = True
    return servidor


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--html", required=True)
    args = parser.parse_args()
    html = Path(args.html).resolve()
    texto = html.read_text(encoding="utf-8")
    match = re.search(r'const WEB_APP_URL = "(https://script\.google\.com/macros/s/[A-Za-z0-9_-]+/exec)"', texto)
    if not match:
        raise ValueError("WEB_APP_URL nao encontrada no HTML do Inspector.")
    chrome = shutil.which("chrome.exe")
    if not chrome:
        for root in ("PROGRAMFILES", "PROGRAMFILES(X86)", "LOCALAPPDATA"):
            candidato = Path(os.environ.get(root, "")) / "Google" / "Chrome" / "Application" / "chrome.exe"
            if candidato.is_file():
                chrome = str(candidato)
                break
    if not chrome:
        raise FileNotFoundError("Google Chrome nao encontrado.")
    token = secrets.token_urlsafe(32)
    consulta = ConsultaLocal(match.group(1))
    servidor = criar_servidor(consulta, token)
    porta = servidor.server_address[1]
    perfil = str(Path(os.environ["LOCALAPPDATA"]) / "Inspector" / "ChromeLocal")
    url = html.as_uri() + "#consultaLocal=" + str(porta) + ":" + token
    subprocess.Popen([chrome, "--disable-web-security", "--user-data-dir=" + perfil, url])
    print("Inspector local iniciado. Mantenha esta janela aberta. Ctrl+C encerra o servico e descarta as credenciais.")
    try:
        servidor.serve_forever()
    except KeyboardInterrupt:
        print("\nEncerrando Inspector local.")
    finally:
        servidor.server_close()
        consulta.cache.clear()


if __name__ == "__main__":
    main()
