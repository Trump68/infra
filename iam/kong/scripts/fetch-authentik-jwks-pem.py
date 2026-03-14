#!/usr/bin/env python3
"""
Получить публичный ключ (PEM) и kid из JWKS провайдера Authentik для настройки Kong JWT plugin.
Требуется: Python 3, пакет cryptography (pip install cryptography).
Использование:
  python3 fetch-authentik-jwks-pem.py [JWKS_URL]
  python3 fetch-authentik-jwks-pem.py [JWKS_URL] --yaml   # готовый YAML для секции consumers
  python3 fetch-authentik-jwks-pem.py [JWKS_URL] --update kong/kong.yml   # подставить в файл и вывести путь
  JWKS_URL по умолчанию: http://localhost:9000/application/o/farmadoc_app/jwks/
  Для приложения с slug farmadoc-app: .../farmadoc-app/jwks/
Вывод: kid и PEM (вставить в kong/kong.yml в consumer.jwt_secrets) или готовая секция consumers при --yaml.
  После обновления kong.yml: docker compose restart kong
"""
import json
import sys
import urllib.request
import base64
import os

try:
    from cryptography.hazmat.primitives.asymmetric.rsa import RSAPublicNumbers
    from cryptography.hazmat.backends import default_backend
    from cryptography.hazmat.primitives import serialization
except ImportError:
    print("Ошибка: нужен пакет cryptography. Установите: pip install cryptography", file=sys.stderr)
    sys.exit(1)


def b64url_decode(s: str) -> int:
    pad = 4 - (len(s) % 4)
    if pad != 4:
        s += "=" * pad
    return int.from_bytes(base64.urlsafe_b64decode(s), "big")


def jwk_to_pem(jwk: dict) -> str:
    if jwk.get("kty") != "RSA":
        raise ValueError("Поддерживается только RSA")
    n = b64url_decode(jwk["n"])
    e = b64url_decode(jwk["e"])
    pub = RSAPublicNumbers(e, n).public_key(default_backend())
    pem = pub.public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
    return pem.decode()


def build_consumers_yaml(keys_data):
    """keys_data = [(kid, pem), ...] — все ключи из JWKS для Kong (JWT по kid из токена)."""
    secrets = []
    for kid, pem in keys_data:
        pem_indent = "\n".join("          " + line for line in pem.strip().split("\n"))
        secrets.append(
            f"      - key: {kid}\n"
            "        algorithm: RS256\n"
            '        secret: "dummy"\n'
            "        rsa_public_key: |\n"
            f"{pem_indent}\n"
        )
    return "consumers:\n  - username: authentik\n    jwt_secrets:\n" + "".join(secrets) + "\n"


def update_kong_yml(kong_yml_path: str, new_consumers: str) -> None:
    with open(kong_yml_path, "r", encoding="utf-8") as f:
        lines = f.readlines()
    start = end = None
    for i, line in enumerate(lines):
        if line.strip() == "consumers:":
            start = i
        if start is not None and line.strip() == "services:" and i > (start or 0):
            end = i
            break
    if start is None or end is None:
        raise SystemExit(f"В файле {kong_yml_path} не найдена секция consumers/services.")
    new_content = "".join(lines[:start]) + new_consumers + "".join(lines[end:])
    with open(kong_yml_path, "w", encoding="utf-8") as f:
        f.write(new_content)


def main():
    default_url = "http://localhost:9000/application/o/farmadoc_app/jwks/"
    opt_yaml = "--yaml" in sys.argv
    opt_update = None
    for i in range(1, len(sys.argv)):
        if sys.argv[i] == "--update" and i + 1 < len(sys.argv):
            opt_update = sys.argv[i + 1]
            break
    url = next(
        (a for a in sys.argv[1:] if a.startswith("http") or a.startswith("file://")),
        default_url,
    )
    try:
        with urllib.request.urlopen(url, timeout=10) as r:
            data = json.load(r)
    except Exception as e:
        print(f"Ошибка запроса {url}: {e}", file=sys.stderr)
        sys.exit(2)
    keys = data.get("keys") or []
    if not keys:
        print("В JWKS нет ключей", file=sys.stderr)
        sys.exit(3)
    keys_data = []
    for k in keys:
        if k.get("kty") != "RSA" or k.get("use") not in (None, "sig"):
            continue
        try:
            kid = k.get("kid") or "authentik-key"
            pem = jwk_to_pem(k)
            keys_data.append((kid, pem))
        except Exception as e:
            print(f"Пропуск ключа {k.get('kid')}: {e}", file=sys.stderr)
    if not keys_data:
        key = keys[0]
        kid = key.get("kid") or "authentik-key"
        pem = jwk_to_pem(key)
        keys_data = [(kid, pem)]
    consumers_yaml = build_consumers_yaml(keys_data)
    if opt_update:
        path = os.path.abspath(opt_update)
        update_kong_yml(path, consumers_yaml)
        print(path)
    elif opt_yaml:
        print("# Замените в kong/kong.yml секцию consumers на:")
        print(consumers_yaml, end="")
    else:
        for i, (kid, pem) in enumerate(keys_data):
            print(f"# Ключ {i + 1} kid (подставить в kong.yml в jwt_secrets[].key):")
            print(kid)
            print("# rsa_public_key:")
            print(pem.strip())
            print()


if __name__ == "__main__":
    main()
