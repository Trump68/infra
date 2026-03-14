#!/usr/bin/env python3
"""
BFF для продакшен-SPA: раздаёт статику, отдаёт конфиг из env, обменивает code на токен (OIDC + PKCE),
проксирует /api в Kong. Запуск: python3 serve.py

Переменные окружения:
  OIDC_DISCOVERY_URL  — URL discovery (например https://auth.example.com/application/o/farmadoc_client/.well-known/openid-configuration/)
  OIDC_CLIENT_ID      — client_id публичного клиента
  OIDC_REDIRECT_URI   — fallback для redirect_uri, если в запросе нет Host; иначе BFF считает redirect_uri из Host (и X-Forwarded-*), чтобы не было invalid_grant при доступе по IP
  KONG_API_BASE_URL   — URL Kong для проксирования /api (пусто = тот же хост, BFF проксирует на KONG_INTERNAL_URL)
  KONG_INTERNAL_URL   — внутренний URL Kong для проксирования (по умолчанию http://localhost:8001)
  PORT                — порт сервера (3000)
"""
import json
import os
import sys
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
# Внутренний URL Authentik для запросов с BFF (Docker: http://authentik-server:9000); для браузера в config отдаётся OIDC_DISCOVERY_URL
AUTHENTIK_INTERNAL_BASE = os.environ.get("AUTHENTIK_INTERNAL_BASE_URL", "").strip().rstrip("/")
# Прокси discovery через BFF (тот же origin — нет CORS). Клиенту всегда отдаём этот путь, если discovery настроен.
BFF_DISCOVERY_PATH = "/auth/.well-known/openid-configuration"
# Явный внутренний URL discovery (если 404 — задайте точный URL из Authentik, например с другим slug)
OIDC_DISCOVERY_INTERNAL = os.environ.get("OIDC_DISCOVERY_INTERNAL_URL", "").strip().rstrip("/")

# Клиенту в config отдаём только BFF-путь (без CORS), никогда прямой URL Authentik
def _client_discovery_url():
    if OIDC_DISCOVERY_URL or OIDC_DISCOVERY_INTERNAL or AUTHENTIK_INTERNAL_BASE:
        return BFF_DISCOVERY_PATH
    return OIDC_DISCOVERY_URL or ""

# Если discovery не задан, собрать из AUTHENTIK_BASE_URL + slug (для локальной разработки)
if not OIDC_DISCOVERY_URL:
    AUTHENTIK_BASE = os.environ.get("AUTHENTIK_BASE_URL", "http://localhost:9000").rstrip("/")
    OIDC_APP_SLUG = os.environ.get("OIDC_APP_SLUG", "farmadoc-app")
    OIDC_DISCOVERY_URL = f"{AUTHENTIK_BASE}/application/o/{OIDC_APP_SLUG}/.well-known/openid-configuration/"
if not OIDC_CLIENT_ID:
    OIDC_CLIENT_ID = os.environ.get("CLIENT_ID", "LxTTZjn6WYpDkdolfVmBpsvskvScMxyfQUFWnmFm")


_token_url_cache = None

def _discovery_url_for_fetch():
    """URL discovery для запроса с BFF (в Docker — внутренний адрес Authentik)."""
    if OIDC_DISCOVERY_INTERNAL:
        return OIDC_DISCOVERY_INTERNAL if OIDC_DISCOVERY_INTERNAL.endswith("/") else OIDC_DISCOVERY_INTERNAL + "/"
    if AUTHENTIK_INTERNAL_BASE and OIDC_DISCOVERY_URL:
        parsed = urllib.parse.urlparse(OIDC_DISCOVERY_URL)
        path = (parsed.path or "/application/o/farmadoc-app/.well-known/openid-configuration").rstrip("/") + "/"
        return f"{AUTHENTIK_INTERNAL_BASE.rstrip('/')}{path}"
    return OIDC_DISCOVERY_URL


def get_token_url():
    """Из discovery URL получить token_endpoint (кэш после первого запроса)."""
    global _token_url_cache
    if _token_url_cache is not None:
        return _token_url_cache
    fetch_url = _discovery_url_for_fetch()
    if not fetch_url:
        return ""
    try:
        req = urllib.request.Request(fetch_url)
        with urllib.request.urlopen(req, timeout=5) as r:
            data = json.load(r)
            token_endpoint = data.get("token_endpoint", "").strip()
            if token_endpoint and not urllib.parse.urlparse(token_endpoint).netloc:
                # Относительный URL — сделать абсолютным (BFF → Authentik)
                base = AUTHENTIK_INTERNAL_BASE or ""
                if not base and OIDC_DISCOVERY_URL:
                    p = urllib.parse.urlparse(OIDC_DISCOVERY_URL)
                    base = f"{p.scheme}://{p.netloc}"
                base = (base or "http://localhost:9000").rstrip("/")
                token_endpoint = urllib.parse.urljoin(base + "/", token_endpoint.lstrip("/"))
            _token_url_cache = token_endpoint
            return _token_url_cache
    except Exception:
        # В Authentik token endpoint — /application/o/token/, а не /application/o/<slug>/token/
        base = fetch_url.split("/.well-known")[0].rstrip("/")
        parts = base.split("/")
        if len(parts) >= 1 and parts[-1] not in ("o", "application"):
            parts[-1] = "token"
        else:
            parts.append("token")
        _token_url_cache = "/".join(parts) + "/"
        return _token_url_cache


def _public_authentik_base():
    """Публичный базовый URL Authentik (для подстановки в discovery при прокси)."""
    if not OIDC_DISCOVERY_URL:
        return ""
    parsed = urllib.parse.urlparse(OIDC_DISCOVERY_URL)
    return f"{parsed.scheme}://{parsed.netloc}".rstrip("/")


def _fetch_and_rewrite_discovery():
    """Загрузить discovery из Authentik и подменить внутренний URL на публичный (редирект из браузера)."""
    fetch_url = _discovery_url_for_fetch()
    if not fetch_url:
        return None, {"error": "discovery_unavailable", "detail": "OIDC_DISCOVERY_URL not configured"}
    # Пробуем с завершающим слэшем и без — Authentik в разных версиях ведёт себя по-разному
    urls_to_try = [fetch_url.rstrip("/") + "/", fetch_url.rstrip("/")]
    urls_to_try = list(dict.fromkeys(urls_to_try))  # без дубликатов
    data = None
    last_error = None
    for url in urls_to_try:
        try:
            req = urllib.request.Request(url)
            with urllib.request.urlopen(req, timeout=5) as r:
                data = json.load(r)
                break
        except urllib.error.HTTPError as e:
            if e.code == 503:
                return None, {
                    "error": "discovery_unavailable",
                    "detail": (
                        "Authentik HTTP 503: Service Unavailable. Обычно Authentik ещё запускается. "
                        "Подождите 1–2 минуты и обновите страницу. Проверка: docker compose logs authentik-server. URL: " + url
                    ),
                }
            last_error = f"Authentik HTTP {e.code}: {e.reason}. Проверьте slug приложения в Authentik и в .env (OIDC_DISCOVERY_URL). URL: {url}"
            if e.code != 404:
                return None, {"error": "discovery_unavailable", "detail": last_error}
        except OSError as e:
            return None, {"error": "discovery_unavailable", "detail": f"Cannot reach Authentik: {e}"}
    if not data:
        return None, {"error": "discovery_unavailable", "detail": last_error or "Authentik returned 404"}
    if not data.get("authorization_endpoint"):
        return None, {"error": "discovery_unavailable", "detail": "Invalid discovery (no authorization_endpoint)"}
    internal_base = AUTHENTIK_INTERNAL_BASE.rstrip("/") if AUTHENTIK_INTERNAL_BASE else ""
    public_base = _public_authentik_base()
    if internal_base and public_base:
        # Подменить внутренний хост на публичный, чтобы браузер редиректил на доступный URL
        data_str = json.dumps(data)
        data_str = data_str.replace(internal_base, public_base)
        data = json.loads(data_str)
    return data, None


class BFFHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=os.path.join(os.path.dirname(__file__)), **kwargs)

    def _redirect_uri_from_request(self):
        """Redirect URI по Host запроса, чтобы совпадал при открытии и на callback (иначе invalid_grant)."""
        host = self.headers.get("X-Forwarded-Host") or self.headers.get("Host") or ""
        proto = self.headers.get("X-Forwarded-Proto") or "http"
        if not host:
            return OIDC_REDIRECT_URI
        return f"{proto.rstrip('/')}://{host.split(',')[0].strip()}/callback"

    def do_GET(self):
        if self.path == "/config.json" or self.path == "/config.json/":
            # Всегда отдаём discovery через BFF (путь того же origin) — браузер не ходит на Authentik, нет CORS
            discovery_url = _client_discovery_url()
            redirect_uri = self._redirect_uri_from_request()
            self.send_json({
                "oidcDiscoveryUrl": discovery_url,
                "clientId": OIDC_CLIENT_ID,
                "redirectUri": redirect_uri,
                "apiBaseUrl": KONG_API_BASE_URL,
            })
            return
        if self.path == BFF_DISCOVERY_PATH or self.path == (BFF_DISCOVERY_PATH + "/"):
            discovery_data, err = _fetch_and_rewrite_discovery()
            if err:
                self.send_json(err, 502)
                return
            self.send_json(discovery_data)
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
            # Используем redirect_uri из тела запроса (SPA сохраняет тот же URI, что подставила в auth URL) — иначе invalid_grant
            redirect_uri = (data.get("redirect_uri") or "").strip()
            if not redirect_uri:
                redirect_uri = self._redirect_uri_from_request()
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
        # Логируем redirect_uri для отладки invalid_grant: в Authentik Redirect URIs должен совпадать побайтово
        print(
            json.dumps({
                "event": "token_exchange",
                "redirect_uri": redirect_uri,
                "host_header": self.headers.get("Host"),
                "token_url": token_url,
            }),
            file=sys.stderr,
            flush=True,
        )
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
            body = e.read().decode()
            print(
                json.dumps({"event": "token_exchange_error", "status": e.code, "body": body, "redirect_uri": redirect_uri}),
                file=sys.stderr,
                flush=True,
            )
            self.send_json({"error": f"{e.code}", "body": body}, e.code)
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
    client_discovery = _client_discovery_url()
    print(f"BFF + SPA: http://localhost:{PORT}/")
    print(f"Redirect URI (fallback): {OIDC_REDIRECT_URI}")
    print(f"Discovery для клиента (без CORS): {client_discovery or '(не задан)'}")
    if client_discovery and OIDC_DISCOVERY_URL:
        print(f"Discovery внутренний (BFF→Authentik): {_discovery_url_for_fetch() or OIDC_DISCOVERY_URL}")
    server.serve_forever()
