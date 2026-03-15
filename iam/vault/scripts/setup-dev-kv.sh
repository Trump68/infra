#!/usr/bin/env bash
# Включает KV v2 и создаёт пример секрета для Farmadoc (dev-режим).
# Запуск: из корня репозитория после docker compose up -d vault
#   ./iam/vault/scripts/setup-dev-kv.sh
# Или: VAULT_ADDR=http://localhost:8200 VAULT_TOKEN=dev-root-token ./iam/vault/scripts/setup-dev-kv.sh

set -e
VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-dev-root-token}"

echo "Using VAULT_ADDR=$VAULT_ADDR"

# Проверка доступности
if ! curl -s -f -o /dev/null "$VAULT_ADDR/v1/sys/health"; then
  echo "Vault is not available at $VAULT_ADDR. Start with: docker compose up -d vault"
  exit 1
fi

# Включить KV v2 по пути secret (идемпотентно: уже включён — не ошибка)
vault secrets enable -path=secret kv-v2 2>/dev/null || true

# Пример секрета для векторной БД (placeholder)
vault kv put secret/farmadoc/vector-db \
  encryption_key="CHANGE-ME-base64-or-key-reference" \
  key_id="current"

echo "Done. KV v2 enabled at secret/. Example: vault kv get secret/farmadoc/vector-db"
echo "Replace encryption_key with a real key for vector DB encryption (see iam/docs/vault.md)."
