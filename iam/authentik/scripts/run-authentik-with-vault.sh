#!/usr/bin/env bash
# Единый скрипт запуска Authentik с секретами из Vault или из .env.
# Использование (из корня репозитория):
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
after_env_only=0
for arg in "$@"; do
  if [[ "$arg" == "--env-only" ]]; then
    ENV_ONLY=1
    after_env_only=1
    continue
  fi
  if [[ $after_env_only -eq 1 ]]; then
    COMPOSE_ARGS+=("$arg")
    continue
  fi
  case "$arg" in
    --from-env)      FROM_ENV=1 ;;
    --prepare-only)  PREPARE_ONLY=1 ;;
  esac
done

# Загрузить .env
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/.env"
  set +a
fi

# ---------- Получить секреты (PG_PASS, AUTHENTIK_SECRET_KEY) ----------
if [[ $FROM_ENV -eq 1 ]]; then
  if [[ ! -f "${REPO_ROOT}/.env" ]]; then
    echo "Ошибка: файл .env не найден. Создайте из .env.example и задайте PG_PASS и AUTHENTIK_SECRET_KEY." >&2
    exit 1
  fi
  if [[ -z "${PG_PASS:-}" || -z "${AUTHENTIK_SECRET_KEY:-}" ]]; then
    echo "Ошибка: в .env должны быть заданы PG_PASS и AUTHENTIK_SECRET_KEY." >&2
    exit 1
  fi
  # уже в окружении после source .env
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
  if ! echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d.get('data') and d['data'].get('data')" 2>/dev/null; then
    echo "Ошибка: секрет secret/farmadoc/authentik не найден. Запишите его (см. iam/docs/vault.md):" >&2
    echo "  vault kv put secret/farmadoc/authentik postgres_password='...' secret_key='...'" >&2
    exit 1
  fi
  PG_PASS=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['data'].get('postgres_password',''))")
  AUTHENTIK_SECRET_KEY=$(echo "$RESP" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['data']['data'].get('secret_key',''))")
  if [[ -z "$PG_PASS" || -z "$AUTHENTIK_SECRET_KEY" ]]; then
    echo "Ошибка: в секрете должны быть ключи postgres_password и secret_key." >&2
    exit 1
  fi
fi

# ---------- Режим --env-only: секреты в окружение, docker compose с переданными аргументами ----------
if [[ $ENV_ONLY -eq 1 ]]; then
  export PG_PASS
  export AUTHENTIK_SECRET_KEY
  cd "$REPO_ROOT"
  if [[ ${#COMPOSE_ARGS[@]} -eq 0 ]]; then
    echo "Ошибка: для --env-only укажите аргументы для docker compose, например: up -d authentik-postgresql authentik-redis authentik-server authentik-worker" >&2
    exit 1
  fi
  exec docker compose "${COMPOSE_ARGS[@]}"
fi

# ---------- Записать .env.vault ----------
if [[ $FROM_ENV -eq 1 ]]; then
  cat > "$ENV_VAULT" << EOF
# Сгенерировано $(date -Iseconds 2>/dev/null || date) из .env (--from-env). Не коммитить.
PG_PASS=${PG_PASS}
AUTHENTIK_SECRET_KEY=${AUTHENTIK_SECRET_KEY}
EOF
  echo "Записано .env.vault из .env."
else
  escape_env_value() { printf '%s' "$1" | sed "s/'/'\\\\''/g"; }
  cat > "$ENV_VAULT" << EOF
# Сгенерировано $(date -Iseconds 2>/dev/null || date) из Vault. Не коммитить.
PG_PASS=$(escape_env_value "$PG_PASS")
AUTHENTIK_SECRET_KEY=$(escape_env_value "$AUTHENTIK_SECRET_KEY")
EOF
  echo "Записано .env.vault из Vault."
fi

[[ $PREPARE_ONLY -eq 1 ]] && exit 0

# ---------- Запуск Authentik ----------
cd "$REPO_ROOT"
exec docker compose up -d authentik-postgresql authentik-redis authentik-server authentik-worker
