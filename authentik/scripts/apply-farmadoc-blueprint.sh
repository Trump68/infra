#!/usr/bin/env bash
# Полный цикл установки Authentik (шаги 2–4): проверка/создание БД authentik, запуск сервисов,
# ожидание готовности API и применение blueprint authentik/blueprints/farmadoc-oidc.yaml.
# Запуск из корня репозитория. Требует: .env с POSTGRES_* и AUTHENTIK_* (или AUTHENTIK_BOOTSTRAP_TOKEN).
# Использование:
#   ./authentik/scripts/apply-farmadoc-blueprint.sh
#   AUTHENTIK_URL=http://localhost:9000 AUTHENTIK_TOKEN=... ./authentik/scripts/apply-farmadoc-blueprint.sh
#   ./authentik/scripts/apply-farmadoc-blueprint.sh http://localhost:9000 your-token
# Пропуск шагов 2–3 (только применение blueprint к уже запущенному Authentik):
#   SKIP_DOCKER_SETUP=1 ./authentik/scripts/apply-farmadoc-blueprint.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BLUEPRINT_FILE="${REPO_ROOT}/authentik/blueprints/farmadoc-oidc.yaml"

if [[ ! -f "$BLUEPRINT_FILE" ]]; then
  echo "Ошибка: файл blueprint не найден: $BLUEPRINT_FILE" >&2
  exit 1
fi

# Сохраняем токен из окружения, чтобы .env его не перезаписал
AUTHENTIK_TOKEN_ENV="${AUTHENTIK_TOKEN:-}"

# Загрузка .env и значения по умолчанию (совместимы с docker-compose.yml)
if [[ -f "${REPO_ROOT}/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/.env"
  set +a
fi
POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-postgres}"

# URL и аргументы: первый аргумент — URL, второй — токен (приоритет: аргумент > env > .env)
AUTHENTIK_URL="${1:-${AUTHENTIK_URL:-http://localhost:9000}}"
AUTHENTIK_TOKEN="${2:-${AUTHENTIK_TOKEN_ENV:-${AUTHENTIK_TOKEN}}}"
if [[ -z "$AUTHENTIK_TOKEN" && -n "${AUTHENTIK_BOOTSTRAP_TOKEN:-}" ]]; then
  AUTHENTIK_TOKEN="$AUTHENTIK_BOOTSTRAP_TOKEN"
fi
AUTHENTIK_URL="${AUTHENTIK_URL%/}"

# --- Шаги 2–3: инфраструктура (можно пропустить через SKIP_DOCKER_SETUP=1) ---

ensure_postgres_running() {
  local max=15
  docker compose -f "${REPO_ROOT}/docker-compose.yml" up -d postgres
  while ! docker exec postgres pg_isready -U "$POSTGRES_USER" -q 2>/dev/null; do
    max=$((max - 1))
    [[ $max -le 0 ]] && { echo "Ошибка: PostgreSQL не готов в течение ожидания." >&2; return 1; }
    sleep 2
  done
}

ensure_authentik_db() {
  local exists
  exists=$(docker exec postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc "SELECT 1 FROM pg_database WHERE datname = 'authentik'" 2>/dev/null || true)
  if [[ "$exists" == "1" ]]; then
    echo "БД authentik уже существует."
    return 0
  fi
  if docker exec postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "CREATE DATABASE authentik;" 2>/dev/null; then
    echo "БД authentik создана."
    return 0
  fi
  echo "Ошибка: не удалось создать БД authentik. Проверьте права и что контейнер postgres запущен." >&2
  return 1
}

start_authentik_services() {
  docker compose -f "${REPO_ROOT}/docker-compose.yml" up -d redis authentik-server authentik-worker
}

# Ожидание готовности сервера (миграции при первом запуске — 1–3 мин).
# Используется /-/health/live/ — в Authentik 2024.x /api/v3/core/version/ может отдавать 404.
wait_for_authentik_api() {
  local max_attempts="${AUTHENTIK_WAIT_ATTEMPTS:-60}"
  local delay="${AUTHENTIK_WAIT_DELAY:-2}"
  local attempt=1 status
  while true; do
    status=$(curl -s -w '%{http_code}' -o /dev/null "${AUTHENTIK_URL}/-/health/live/" 2>/dev/null || echo "000")
    if [[ "$status" == "200" ]]; then
      echo "Authentik готов (health check OK)."
      return 0
    fi
    if [[ $attempt -ge $max_attempts ]]; then
      echo "Ошибка: Authentik не ответил за отведённое время (попыток: ${max_attempts}). Проверьте: docker compose logs -f authentik-server" >&2
      return 1
    fi
    echo "Ожидание Authentik... попытка ${attempt}/${max_attempts} (HTTP ${status})"
    sleep "$delay"
    attempt=$((attempt + 1))
  done
}

# --- Применение blueprint (шаг 4) ---

# Вариант 1: Flow/Blueprint import (разовая загрузка YAML)
# В части версий Authentik: POST /api/v3/flows/instances/import/ с телом YAML или multipart file
import_via_flow_import() {
  local status
  status=$(curl -s -w '%{http_code}' -o /tmp/authentik_import_resp.txt \
    -X POST "${AUTHENTIK_URL}/api/v3/flows/instances/import/" \
    -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
    -H "Content-Type: application/yaml" \
    --data-binary "@${BLUEPRINT_FILE}")
  if [[ "$status" == "204" || "$status" == "200" ]]; then
    echo "Blueprint применён (flows/instances/import), статус: ${status}"
    return 0
  fi
  return 1
}

# Вариант 2: Managed blueprints — создать instance с content и name, затем apply
import_via_managed() {
  local create_url apply_url uuid status body_file
  create_url="${AUTHENTIK_URL}/api/v3/managed/blueprints/"
  body_file="${TMPDIR:-/tmp}/authentik_blueprint_body_$$.json"
  if jq -n --rawfile content "$BLUEPRINT_FILE" '{name: "farmadoc-oidc", content: $content}' > "$body_file" 2>/dev/null; then
    :
  elif BODY_FILE="$body_file" BLUEPRINT_FILE="$BLUEPRINT_FILE" python3 -c "
import os, json
with open(os.environ['BLUEPRINT_FILE']) as f:
    c = f.read()
with open(os.environ['BODY_FILE'], 'w') as f:
    json.dump({'name': 'farmadoc-oidc', 'content': c}, f)
" 2>/dev/null; then
    :
  else
    echo "Для варианта managed нужен jq или python3" >&2
    rm -f "$body_file"
    return 1
  fi
  status=$(curl -s -w '%{http_code}' -o /tmp/authentik_create_resp.txt \
    -X POST "$create_url" \
    -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "@${body_file}")
  rm -f "$body_file"
  if [[ "$status" != "201" ]]; then
    echo "Создание managed blueprint: HTTP ${status}" >&2
    cat /tmp/authentik_create_resp.txt 2>/dev/null | head -20
    if [[ "$status" == "405" ]]; then
      echo "Подсказка: при 405 примените blueprint вручную: Customization → Blueprints → Apply blueprint → загрузите ${BLUEPRINT_FILE}" >&2
    fi
    return 1
  fi
  uuid=$(jq -r '.pk // .id // .uuid // empty' /tmp/authentik_create_resp.txt 2>/dev/null) || \
  uuid=$(python3 -c "import json; d=json.load(open('/tmp/authentik_create_resp.txt')); print(d.get('pk') or d.get('id') or d.get('uuid') or '')" 2>/dev/null) || \
  uuid=$(grep -oE '"(pk|id|uuid)":"[^"]+"' /tmp/authentik_create_resp.txt | head -1 | cut -d'"' -f4)
  if [[ -z "$uuid" ]]; then
    echo "Не удалось извлечь ID созданного blueprint" >&2
    cat /tmp/authentik_create_resp.txt
    return 1
  fi
  apply_url="${AUTHENTIK_URL}/api/v3/managed/blueprints/${uuid}/apply/"
  status=$(curl -s -w '%{http_code}' -o /tmp/authentik_apply_resp.txt \
    -X POST "$apply_url" \
    -H "Authorization: Bearer ${AUTHENTIK_TOKEN}")
  if [[ "$status" == "200" ]]; then
    echo "Blueprint создан и применён (managed blueprints), instance: ${uuid}"
    return 0
  fi
  echo "Apply blueprint: HTTP ${status}" >&2
  cat /tmp/authentik_apply_resp.txt 2>/dev/null
  return 1
}

# Вариант 3: Managed blueprints с multipart/form-data (file upload), если API поддерживает
import_via_managed_file() {
  local create_url apply_url uuid status
  create_url="${AUTHENTIK_URL}/api/v3/managed/blueprints/"
  status=$(curl -s -w '%{http_code}' -o /tmp/authentik_create_resp.txt \
    -X POST "$create_url" \
    -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
    -F "file=@${BLUEPRINT_FILE}")
  if [[ "$status" != "201" ]]; then
    return 1
  fi
  uuid=$(jq -r '.pk // .id // .uuid // empty' /tmp/authentik_create_resp.txt 2>/dev/null) || \
  uuid=$(python3 -c "import json; d=json.load(open('/tmp/authentik_create_resp.txt')); print(d.get('pk') or d.get('id') or d.get('uuid') or '')" 2>/dev/null)
  if [[ -z "$uuid" ]]; then
    return 1
  fi
  apply_url="${AUTHENTIK_URL}/api/v3/managed/blueprints/${uuid}/apply/"
  status=$(curl -s -w '%{http_code}' -o /tmp/authentik_apply_resp.txt \
    -X POST "$apply_url" \
    -H "Authorization: Bearer ${AUTHENTIK_TOKEN}")
  if [[ "$status" == "200" ]]; then
    echo "Blueprint загружен (file) и применён, instance: ${uuid}"
    return 0
  fi
  return 1
}

# --- Основной поток ---

echo "Authentik: ${AUTHENTIK_URL}"
echo "Blueprint:  ${BLUEPRINT_FILE}"
echo ""

if [[ -z "${SKIP_DOCKER_SETUP:-}" || "$SKIP_DOCKER_SETUP" == "0" ]]; then
  echo "[1/5] Запуск PostgreSQL..."
  (cd "$REPO_ROOT" && ensure_postgres_running) || exit 1

  echo "[2/5] Проверка/создание БД authentik..."
  (cd "$REPO_ROOT" && ensure_authentik_db) || exit 1

  echo "[3/5] Запуск Redis и Authentik (server, worker)..."
  (cd "$REPO_ROOT" && start_authentik_services) || exit 1
else
  echo "Пропуск шагов 2–3 (SKIP_DOCKER_SETUP=1)."
fi

if [[ -z "$AUTHENTIK_TOKEN" ]]; then
  echo "Ошибка: нужен AUTHENTIK_TOKEN или AUTHENTIK_BOOTSTRAP_TOKEN (в .env или аргументом)." >&2
  echo "Использование: $0 [AUTHENTIK_URL] [AUTHENTIK_TOKEN]" >&2
  exit 1
fi
if [[ -n "${AUTHENTIK_BOOTSTRAP_TOKEN:-}" && "$AUTHENTIK_TOKEN" == "$AUTHENTIK_BOOTSTRAP_TOKEN" ]]; then
  echo "Используется AUTHENTIK_BOOTSTRAP_TOKEN (bootstrap)."
else
  echo "Используется переданный AUTHENTIK_TOKEN."
fi

echo "[4/5] Ожидание готовности Authentik API..."
wait_for_authentik_api || exit 1

echo "[5/5] Применение blueprint..."
# Сначала managed (JSON) — основной способ; при 405 в части версий Authentik см. подсказку ниже
if import_via_managed; then
  echo ""
  echo "Готово. Провайдер и приложение: Directory → Providers, Directory → Applications (Farmadoc OIDC, farmadoc_client)."
  exit 0
fi
if import_via_flow_import; then
  echo ""
  echo "Готово. Провайдер и приложение: Directory → Providers, Directory → Applications (Farmadoc OIDC, farmadoc_client)."
  exit 0
fi
if import_via_managed_file; then
  echo ""
  echo "Готово. Провайдер и приложение: Directory → Providers, Directory → Applications (Farmadoc OIDC, farmadoc_client)."
  exit 0
fi

echo ""
echo "Не удалось применить blueprint ни одним из способов." >&2
echo "Проверьте Swagger: ${AUTHENTIK_URL}/api/v3/schema/swagger/" >&2
echo "Альтернатива: Customization → Blueprints → Apply blueprint (загрузить файл вручную)." >&2
exit 1
