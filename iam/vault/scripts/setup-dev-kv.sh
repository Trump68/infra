#!/usr/bin/env bash
# Включает KV v2 и создаёт путь для секретов Authentik (dev-режим).
# Требуется только curl (Vault CLI не нужен). Запуск из корня репозитория после docker compose up -d vault:
#   ./iam/vault/scripts/setup-dev-kv.sh
#   ./iam/vault/scripts/setup-dev-kv.sh --write-from-env   # записать PG_PASS и AUTHENTIK_SECRET_KEY из .env в Vault (шаг 2)
# Или: VAULT_ADDR=http://localhost:8200 VAULT_TOKEN=dev-root-token ./iam/vault/scripts/setup-dev-kv.sh [--write-from-env]

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

WRITE_FROM_ENV=0
for arg in "$@"; do
  case "$arg" in
    --write-from-env) WRITE_FROM_ENV=1 ;;
  esac
done

VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-dev-root-token}"

echo "Using VAULT_ADDR=$VAULT_ADDR"

# Проверка доступности
if ! curl -s -f -o /dev/null "$VAULT_ADDR/v1/sys/health"; then
  echo "Vault is not available at $VAULT_ADDR. Start with: docker compose up -d vault"
  exit 1
fi

# Включить KV v2 по пути secret (идемпотентно: 400 = уже включён)
resp=$(curl -s -w '\n%{http_code}' -X POST -H "X-Vault-Token: $VAULT_TOKEN" -H "Content-Type: application/json" \
  -d '{"type":"kv","options":{"version":2}}' "$VAULT_ADDR/v1/sys/mounts/secret")
code=$(echo "$resp" | tail -n1)
if [[ "$code" != "200" && "$code" != "400" ]]; then
  echo "Failed to enable KV v2 at secret/ (HTTP $code)" >&2
  exit 1
fi

# Секреты Authentik: из .env или placeholder
if [[ $WRITE_FROM_ENV -eq 1 ]]; then
  if [[ -f "${REPO_ROOT}/.env" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${REPO_ROOT}/.env"
    set +a
  fi
  if [[ -z "${PG_PASS:-}" || -z "${AUTHENTIK_SECRET_KEY:-}" ]]; then
    echo "Ошибка: в .env задайте PG_PASS и AUTHENTIK_SECRET_KEY для записи в Vault." >&2
    exit 1
  fi
  # Экранируем для JSON: обратная косая черта и кавычки
  PG_ESC=$(echo "$PG_PASS" | sed 's/\\/\\\\/g; s/"/\\"/g')
  SK_ESC=$(echo "$AUTHENTIK_SECRET_KEY" | sed 's/\\/\\\\/g; s/"/\\"/g')
  BODY="{\"data\":{\"postgres_password\":\"$PG_ESC\",\"secret_key\":\"$SK_ESC\"}}"
  curl -s -X POST -H "X-Vault-Token: $VAULT_TOKEN" -H "Content-Type: application/json" \
    -d "$BODY" "$VAULT_ADDR/v1/secret/data/farmadoc/authentik" -f -o /dev/null
  echo "Done. KV v2 enabled at secret/. Authentik secrets written from .env to secret/farmadoc/authentik."
  echo "Run: ./iam/authentik/scripts/run-authentik-with-vault.sh (see iam/docs/vault.md)."
else
  # Пример секретов Authentik (placeholder — замените на реальные или запустите с --write-from-env)
  curl -s -X POST -H "X-Vault-Token: $VAULT_TOKEN" -H "Content-Type: application/json" \
    -d '{"data":{"postgres_password":"CHANGE-ME","secret_key":"CHANGE-ME"}}' \
    "$VAULT_ADDR/v1/secret/data/farmadoc/authentik" -f -o /dev/null
  echo "Done. KV v2 enabled at secret/. Authentik path: secret/farmadoc/authentik (postgres_password, secret_key)."
  echo "To write secrets from .env: ./iam/vault/scripts/setup-dev-kv.sh --write-from-env"
  echo "Then: ./iam/authentik/scripts/run-authentik-with-vault.sh (see iam/docs/vault.md)."
fi
