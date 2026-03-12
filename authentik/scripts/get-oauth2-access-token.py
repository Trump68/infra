#!/usr/bin/env python3
"""
Получить OAuth2 access_token от Authentik (authorization code flow).
Запускает локальный HTTP-сервер для приёма редиректа, выводит ссылку для входа,
после входа обменивает code на access_token и печатает его.

Переменные окружения (опционально):
  AUTHENTIK_URL     — базовый URL Authentik (по умолчанию http://192.168.173.157:9000)
  CLIENT_ID         — Client ID провайдера
  REDIRECT_URI      — redirect_uri провайдера (по умолчанию http://localhost:3000/callback)
  KONG_URL          — если задан, после получения токена проверяет запрос к Kong (http://IP:8001)

Использование:
  python3 get-oauth2-access-token.py
  AUTHENTIK_URL=http://localhost:9000 CLIENT_ID=xxx python3 get-oauth2-access-token.py
  KONG_URL=http://192.168.173.157:8001 python3 get-oauth2-access-token.py
"""
import json
import os
import sys
import urllib.parse
import urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler

AUTHENTIK_URL = os.environ.get("AUTHENTIK_URL", "http://192.168.173.157:9000").rstrip("/")
CLIENT_ID = os.environ.get("CLIENT_ID", "LxTTZjn6WYpDkdolfVmBpsvskvScMxyfQUFWnmFm")
REDIRECT_URI = os.environ.get("REDIRECT_URI", "http://localhost:3000/callback")
KONG_URL = os.environ.get("KONG_URL", "")
received_code = None

AUTHORIZE_URL = f"{AUTHENTIK_URL}/application/o/authorize/"
TOKEN_URL = f"{AUTHENTIK_URL}/application/o/token/"


def run_callback_server(host: str, port: int, path: str):
    class CallbackHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            global received_code
            parsed = urllib.parse.urlparse(self.path)
            if parsed.path.rstrip("/") == path.rstrip("/") and parsed.query:
                params = urllib.parse.parse_qs(parsed.query)
                if "code" in params:
                    received_code = params["code"][0]
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(b"<html><body><p>OK. You can close this tab.</p></body></html>")

        def log_message(self, *args):
            pass

    HTTPServer((host, port), CallbackHandler).handle_request()


def main():
    parsed = urllib.parse.urlparse(REDIRECT_URI)
    host = parsed.hostname or "localhost"
    port = parsed.port or 3000
    path = parsed.path or "/callback"

    auth_url = (
        f"{AUTHORIZE_URL}?response_type=code"
        f"&client_id={urllib.parse.quote(CLIENT_ID)}"
        f"&redirect_uri={urllib.parse.quote(REDIRECT_URI)}&scope=openid"
    )
    print(f"1. Open in browser:\n   {auth_url}\n")
    print("2. Waiting for redirect to", REDIRECT_URI, "...")
    run_callback_server(host, port, path)

    if not received_code:
        print("No code received. Check redirect_uri in provider:", REDIRECT_URI, file=sys.stderr)
        sys.exit(2)

    print("3. Exchanging code for token (POST", TOKEN_URL, ")...")
    data = urllib.parse.urlencode({
        "grant_type": "authorization_code",
        "code": received_code,
        "redirect_uri": REDIRECT_URI,
        "client_id": CLIENT_ID,
    }).encode()
    req = urllib.request.Request(TOKEN_URL, data=data, method="POST",
                                 headers={"Content-Type": "application/x-www-form-urlencoded"})
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            token_data = json.load(r)
    except urllib.error.HTTPError as e:
        print(f"Token error {e.code}: {e.read().decode()}", file=sys.stderr)
        sys.exit(3)

    access_token = token_data.get("access_token")
    if not access_token:
        print("No access_token:", token_data, file=sys.stderr)
        sys.exit(4)

    print("\nAccess token:")
    print(access_token)

    if KONG_URL:
        url = f"{KONG_URL.rstrip('/')}/api/" if not KONG_URL.endswith("/api") else KONG_URL
        if not url.endswith("/"):
            url += "/"
        print(f"\n4. Testing Kong {url}...")
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {access_token}"})
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                print(f"   Kong: {r.status}")
        except urllib.error.HTTPError as e:
            print(f"   Kong: {e.code}")


if __name__ == "__main__":
    main()
