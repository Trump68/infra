#!/usr/bin/env python3
"""
Сервер тестового SPA: раздаёт index.html, обменивает code на токен (Authentik),
проксирует /api/* в Kong. Запуск: python3 serve.py [port]
Переменные: AUTHENTIK_URL, CLIENT_ID, KONG_URL (по умолчанию http://localhost:8001).
Redirect URI приложения должен быть http://localhost:PORT/callback (PORT по умолчанию 3000).
"""
import json
import os
import urllib.error
import urllib.parse
import urllib.request
from http.server import HTTPServer, SimpleHTTPRequestHandler

PORT = int(os.environ.get("PORT", "3000"))
AUTHENTIK_URL = os.environ.get("AUTHENTIK_URL", "http://192.168.173.157:9000").rstrip("/")
CLIENT_ID = os.environ.get("CLIENT_ID", "LxTTZjn6WYpDkdolfVmBpsvskvScMxyfQUFWnmFm")
KONG_URL = os.environ.get("KONG_URL", "http://192.168.173.157:8001").rstrip("/")
TOKEN_URL = f"{AUTHENTIK_URL}/application/o/token/"


class SPAHandler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=os.path.join(os.path.dirname(__file__)), **kwargs)

    def do_GET(self):
        if self.path == "/config" or self.path == "/config/":
            self.send_json({"authentikUrl": AUTHENTIK_URL, "clientId": CLIENT_ID, "kongUrl": KONG_URL})
            return
        if self.path.startswith("/api"):
            self.proxy_to_kong()
            return
        if self.path in ("/", "/callback", "/callback/") or self.path.startswith("/callback?"):
            self.path = "/index.html"
        return super().do_GET()

    def do_POST(self):
        if self.path == "/exchange" or self.path == "/exchange/":
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
            redirect_uri = data.get("redirect_uri", "")
            if not code:
                self.send_json({"error": "missing code"}, 400)
                return
        except (ValueError, json.JSONDecodeError) as e:
            self.send_json({"error": str(e)}, 400)
            return
        post_data = urllib.parse.urlencode({
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirect_uri,
            "client_id": CLIENT_ID,
        }).encode()
        req = urllib.request.Request(TOKEN_URL, data=post_data, method="POST",
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
        url = f"{KONG_URL}{path}"
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
    server = HTTPServer(("", PORT), SPAHandler)
    print(f"SPA test server: http://localhost:{PORT}/")
    print(f"Redirect URI for Authentik: http://localhost:{PORT}/callback")
    server.serve_forever()
