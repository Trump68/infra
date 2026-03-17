#!/usr/bin/env bash
# Единый скрипт запуска Authentik с секретами из Vault или из .env.
# Запуск из корня репозитория:
#   ./iam/authentik/scripts/run-authentik-with-vault.sh              # секреты из Vault, .env.vault + docker compose up
#   ./iam/authentik/scripts/run-authentik-with-vault.sh --from-env   # секреты из .env, .env.vault + docker compose up
#   ./iam/authentik/scripts/run-authentik-with-vault.sh --prepare-only       # только создать .env.vault из Vault
#   ./iam/authentik/scripts/run-authentik-with-vault.sh --prepare-only --from-env  # только .env.vault из .env
#   ./iam/authentik/scripts/run-authentik-with-vault.sh --env-only [--from-env] up -d ...  # секреты в env, без .env.vault; аргументы — в docker compose
# Требует: для режима Vault — запущенный vault, секрет secret/farmadoc/authentik (postgres_password, secret_key);
#   VAULT_ADDR, VAULT_TOKEN (или VAULT_DEV_ROOT_TOKEN_ID) в .env или окружении.
# См. iam/docs/vault.md

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
ENV_VAULT="${REPO_ROOT}/.env.vault"

FROM_ENV=0
PREPARE_ONLY=0
ENV_ONLY=0
COMPOSE_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --from-env)   FROM_ENV=1; shift ;;
    --prepare-only) PREPARE_ONLY=1; shift ;;
    --env-only)   ENV_ONLY=1; shift ;;
    *)            COMPOSE_ARGS+=("$1"); shift ;;
  esac
done

# ---------- Загрузить .env ----------
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/.env"
  set +a
fi

# ---------- Получить секреты из Vault или из .env ----------
if [[ $FROM_ENV -eq 1 ]]; then
  if [[ -z "${PG_PASS:-}" || -z "${AUTHENTIK_SECRET_KEY:-}" ]]; then
    echo "Ошибка: в .env задайте PG_PASS и AUTHENTIK_SECRET_KEY." >&2
    exit 1
  fi
else
  VAULT_ADDR="${VAULT_ADDR:-http://localhost:8200}"
  VAULT_TOKEN="${VAULT_TOKEN:-${VAULT_DEV_ROOT_TOKEN_ID:-}}"
  VAULT_PATH="secret/data/farmadoc/authentik"
  if [[ -z "$VAULT_TOKEN" ]]; then
    echo "Ошибка: задайте VAULT_TOKEN или VAULT_DEV_ROOT_TOKEN_ID (в .env или окружении)." >&2
    exit 1
  fi
  RESP=$(curl -s -S -H "X-Vault-Token: ${VAULT_TOKEN}" "${VAULT_ADDR}/v1/${VAULT_PATH}" 2>/dev/null) || true
  if [[ -z "$RESP" ]]; then
    echo "Ошибка: не удалось обратиться к Vault по ${VAULT_ADDR}. Запустите: docker compose up -d vault" >&2
    exit 1
  fi
  if ! echo "$RESP" | grep -q '"data"'; then
    echo "Ошибка: секрет secret/farmadoc/authentik не найден. Запишите его (см. iam/docs/vault.md):" >&2
    echo "  curl -X POST -H \"X-Vault-Token: \$VAULT_TOKEN\" -d '{\"data\":{\"postgres_password\":\"...\",\"secret_key\":\"...\"}}' \"\$VAULT_ADDR/v1/secret/data/farmadoc/authentik\"" >&2
    exit 1
  fi
  PG_PASS=$(echo "$RESP" | sed -n 's/.*"postgres_password":"\([^"]*\)".*/\1/p')
  AUTHENTIK_SECRET_KEY=$(echo "$RESP" | sed -n 's/.*"secret_key":"\([^"]*\)".*/\1/p')
  if [[ -z "$PG_PASS" || -z "$AUTHENTIK_SECRET_KEY" ]]; then
    echo "Ошибка: в секрете Vault должны быть ключи postgres_password и secret_key." >&2
    exit 1
  fi
fi

# ---------- Режим --env-only: экспорт в окружение и передача аргументов в docker compose ----------
if [[ $ENV_ONLY -eq 1 ]]; then
  export PG_PASS
  export AUTHENTIK_SECRET_KEY
  if [[ ${#COMPOSE_ARGS[@]} -eq 0 ]]; then
    set -- up -d authentik-postgresql authentik-redis authentik-server authentik-worker
  else
    set -- "${COMPOSE_ARGS[@]}"
  fi
  cd "$REPO_ROOT" && docker compose "$@"
  exit 0
fi

# ---------- Записать .env.vault ----------
if [[ $FROM_ENV -eq 1 ]]; then
  cat > "$ENV_VAULT" << EOF
# Сгенерировано из .env $(date -Iseconds 2>/dev/null || date). Не коммитить.
PG_PASS=$PG_PASS
AUTHENTIK_SECRET_KEY=$AUTHENTIK_SECRET_KEY
EOF
  echo "Записано .env.vault из .env."
else
  cat > "$ENV_VAULT" << EOF
# Сгенерировано $(date -Iseconds 2>/dev/null || date) из Vault. Не коммитить.
PG_PASS=$PG_PASS
AUTHENTIK_SECRET_KEY=$AUTHENTIK_SECRET_KEY
EOF
  echo "Записано .env.vault из Vault."
fi

[[ $PREPARE_ONLY -eq 1 ]] && exit 0

# ---------- Запуск контейнеров Authentik ----------
cd "$REPO_ROOT"
docker compose up -d authentik-postgresql authentik-redis authentik-server authentik-worker
