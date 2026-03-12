#!/usr/bin/env python3
"""
BFF для продакшен-SPA: раздаёт статику, отдаёт конфиг из env, обменивает code на токен (OIDC + PKCE),
проксирует /api в Kong. Запуск: python3 serve.py

Переменные окружения:
  OIDC_DISCOVERY_URL  — URL discovery (например https://auth.example.com/application/o/farmadoc_client/.well-known/openid-configuration/)
  OIDC_CLIENT_ID      — client_id публичного клиента
  OIDC_REDIRECT_URI   — redirect_uri (например https://app.example.com/callback); по умолчанию http://localhost:3000/callback
  KONG_API_BASE_URL   — URL Kong для проксирования /api (пусто = тот же хост, BFF проксирует на KONG_INTERNAL_URL)
  KONG_INTERNAL_URL   — внутренний URL Kong для проксирования (по умолчанию http://localhost:8001)
  PORT                — порт сервера (3000)
"""
import json
import os
import urllib.error
import urllib.parse
import urllib.request
from http.server import HTTPServer, SimpleHTTPRequestHandler

PORT = int(os.environ.get("PORT", "3000"))
OIDC_DISCOVERY_URL = os.environ.get("OIDC_DISCOVERY_URL", "").strip() or os.environ.get("OIDC_ISSUER", "").strip()
OIDC_CLIENT_ID = os.environ.get("OIDC_CLIENT_ID", "").strip()
OIDC_REDIRECT_URI = os.environ.get("OIDC_REDIRECT_URI", f"http://localhost:{PORT}/callback").strip()
KONG_API_BASE_URL = os.environ.get("KONG_API_BASE_URL", "").strip()
KONG_INTERNAL_URL = os.environ.get("KONG_INTERNAL_URL", "http://localhost:8001").rstrip("/")

# Если discovery не задан, собрать из AUTHENTIK_BASE_URL + slug (для локальной разработки)
if not OIDC_DISCOVERY_URL:
    AUTHENTIK_BASE = os.environ.get("AUTHENTIK_BASE_URL", "http://localhost:9000").rstrip("/")
    OIDC_APP_SLUG = os.environ.get("OIDC_APP_SLUG", "farmadoc_client")
    OIDC_DISCOVERY_URL = f"{AUTHENTIK_BASE}/application/o/{OIDC_APP_SLUG}/.well-known/openid-configuration/"
if not OIDC_CLIENT_ID:
    OIDC_CLIENT_ID = os.environ.get("CLIENT_ID", "LxTTZjn6WYpDkdolfVmBpsvskvScMxyfQUFWnmFm")


_token_url_cache = None

def get_token_url():
    """Из discovery URL получить token_endpoint (кэш после первого запроса)."""
    global _token_url_cache
    if _token_url_cache is not None:
        return _token_url_cache
    if not OIDC_DISCOVERY_URL:
        return ""
    try:
        req = urllib.request.Request(OIDC_DISCOVERY_URL)
        with urllib.request.urlopen(req, timeout=5) as r:
            data = json.load(r)
            _token_url_cache = data.get("token_endpoint", "")
            return _token_url_cache
    except Exception:
        base = OIDC_DISCOVERY_URL.replace("/.well-known/openid-configuration/", "").replace("/.well-known/openid-configuration", "")
        _token_url_cache = f"{base}/token/"
        return _token_url_cache


class BFFHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=os.path.join(os.path.dirname(__file__)), **kwargs)

    def do_GET(self):
        if self.path == "/config.json" or self.path == "/config.json/":
            self.send_json({
                "oidcDiscoveryUrl": OIDC_DISCOVERY_URL,
                "clientId": OIDC_CLIENT_ID,
                "redirectUri": OIDC_REDIRECT_URI,
                "apiBaseUrl": KONG_API_BASE_URL,
            })
            return
        if self.path.startswith("/api"):
            self.proxy_to_kong()
            return
        if self.path in ("/", "/callback", "/callback/") or self.path.startswith("/callback?"):
            self.path = "/index.html"
        return super().do_GET()

    def do_POST(self):
        if self.path == "/auth/exchange" or self.path == "/auth/exchange/":
            self.handle_exchange()
            return
        self.send_error(404)

    def send_json(self, data, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode("utf-8"))

    def handle_exchange(self):
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length)
            data = json.loads(body.decode("utf-8"))
            code = data.get("code")
            code_verifier = data.get("code_verifier")
            redirect_uri = data.get("redirect_uri", OIDC_REDIRECT_URI)
            if not code:
                self.send_json({"error": "missing code"}, 400)
                return
            if not code_verifier:
                self.send_json({"error": "missing code_verifier (PKCE)"}, 400)
                return
        except (ValueError, json.JSONDecodeError) as e:
            self.send_json({"error": str(e)}, 400)
            return
        token_url = get_token_url()
        if not token_url:
            self.send_json({"error": "token_endpoint not configured"}, 502)
            return
        post_data = urllib.parse.urlencode({
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirect_uri,
            "client_id": OIDC_CLIENT_ID,
            "code_verifier": code_verifier,
        }).encode()
        req = urllib.request.Request(token_url, data=post_data, method="POST",
                                     headers={"Content-Type": "application/x-www-form-urlencoded"})
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                token_data = json.load(r)
            self.send_json(token_data)
        except urllib.error.HTTPError as e:
            self.send_json({"error": f"{e.code}", "body": e.read().decode()}, e.code)
        except OSError as e:
            self.send_json({"error": str(e)}, 502)

    def proxy_to_kong(self):
        path = self.path
        if path == "/api" or path == "/api/":
            path = "/api/"
        url = f"{KONG_INTERNAL_URL}{path}"
        auth = self.headers.get("Authorization")
        req = urllib.request.Request(url, method="GET", headers={"Authorization": auth} if auth else {})
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                body = r.read()
                self.send_response(r.status)
                for k, v in r.headers.items():
                    if k.lower() not in ("transfer-encoding", "connection"):
                        self.send_header(k, v)
                self.end_headers()
                self.wfile.write(body)
        except urllib.error.HTTPError as e:
            body = e.read()
            self.send_response(e.code)
            self.send_header("Content-Type", "text/plain; charset=utf-8")
            self.end_headers()
            self.wfile.write(body)
        except OSError as e:
            self.send_json({"error": str(e)}, 502)


if __name__ == "__main__":
    server = HTTPServer(("", PORT), BFFHandler)
    print(f"BFF + SPA: http://localhost:{PORT}/")
    print(f"Redirect URI: {OIDC_REDIRECT_URI}")
    print(f"OIDC Discovery: {OIDC_DISCOVERY_URL}")
    server.serve_forever()
