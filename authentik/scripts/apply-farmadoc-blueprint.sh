#!/usr/bin/env bash
# Загружает blueprint authentik/blueprints/farmadoc-oidc.yaml в Authentik через API и применяет его.
# Требует: AUTHENTIK_URL и AUTHENTIK_TOKEN (или передать как аргументы).
# Использование:
#   AUTHENTIK_URL=http://localhost:9000 AUTHENTIK_TOKEN=... ./apply-farmadoc-blueprint.sh
#   ./apply-farmadoc-blueprint.sh http://localhost:9000 your-token

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BLUEPRINT_FILE="${REPO_ROOT}/authentik/blueprints/farmadoc-oidc.yaml"

if [[ ! -f "$BLUEPRINT_FILE" ]]; then
  echo "Ошибка: файл blueprint не найден: $BLUEPRINT_FILE" >&2
  exit 1
fi

AUTHENTIK_URL="${1:-${AUTHENTIK_URL}}"
AUTHENTIK_TOKEN="${2:-${AUTHENTIK_TOKEN}}"
# Для первого запуска можно задать только AUTHENTIK_BOOTSTRAP_TOKEN в .env — скрипт подставит его как токен
if [[ -z "$AUTHENTIK_TOKEN" && -n "${AUTHENTIK_BOOTSTRAP_TOKEN:-}" ]]; then
  AUTHENTIK_TOKEN="$AUTHENTIK_BOOTSTRAP_TOKEN"
  echo "Используется AUTHENTIK_BOOTSTRAP_TOKEN (bootstrap)." >&2
fi

if [[ -z "$AUTHENTIK_URL" || -z "$AUTHENTIK_TOKEN" ]]; then
  echo "Использование: $0 [AUTHENTIK_URL] [AUTHENTIK_TOKEN]" >&2
  echo "  или задайте переменные AUTHENTIK_URL и AUTHENTIK_TOKEN (или AUTHENTIK_BOOTSTRAP_TOKEN для первого запуска)" >&2
  echo "  Пример: AUTHENTIK_URL=http://localhost:9000 AUTHENTIK_TOKEN=your-token $0" >&2
  exit 1
fi

# Убираем завершающий слэш
AUTHENTIK_URL="${AUTHENTIK_URL%/}"

echo "Authentik: ${AUTHENTIK_URL}"
echo "Blueprint:  ${BLUEPRINT_FILE}"
echo ""

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

# Вариант 2: Managed blueprints — создать instance с content, затем apply
import_via_managed() {
  local create_url apply_url uuid status body
  create_url="${AUTHENTIK_URL}/api/v3/managed/blueprints/"
  body=$(jq -n --rawfile content "$BLUEPRINT_FILE" '{content: $content}' 2>/dev/null) || \
  body=$(python3 -c "import json; print(json.dumps({'content': open('${BLUEPRINT_FILE}').read()}))" 2>/dev/null)
  if [[ -z "$body" ]]; then
    echo "Для варианта managed нужен jq или python3" >&2
    return 1
  fi
  status=$(curl -s -w '%{http_code}' -o /tmp/authentik_create_resp.txt \
    -X POST "$create_url" \
    -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$body")
  if [[ "$status" != "201" ]]; then
    echo "Создание managed blueprint: HTTP ${status}" >&2
    cat /tmp/authentik_create_resp.txt 2>/dev/null | head -20
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

# Проверка доступности API
check_auth() {
  local status
  status=$(curl -s -w '%{http_code}' -o /dev/null \
    -H "Authorization: Bearer ${AUTHENTIK_TOKEN}" \
    "${AUTHENTIK_URL}/api/v3/core/version/")
  if [[ "$status" == "200" ]]; then
    return 0
  fi
  echo "Ошибка: API недоступен или неверный токен (HTTP ${status})" >&2
  return 1
}

check_auth || exit 1

if import_via_flow_import; then
  exit 0
fi
if import_via_managed_file; then
  exit 0
fi
if import_via_managed; then
  exit 0
fi

echo ""
echo "Не удалось применить blueprint ни одним из способов." >&2
echo "Проверьте Swagger вашего Authentik: ${AUTHENTIK_URL}/api/v3/schema/swagger/" >&2
echo "Альтернатива: загрузите файл вручную: Customization → Blueprints → Apply blueprint." >&2
exit 1
