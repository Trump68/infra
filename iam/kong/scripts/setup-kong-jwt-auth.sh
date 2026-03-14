#!/usr/bin/env bash
# Автоматическая настройка Kong JWT: получение ключа из JWKS Authentik, подстановка в iam/kong/kong.yml, перезапуск Kong.
# Запуск из корня репозитория. Требует: Authentik запущен, провайдер создан (см. iam/docs/authentik.md).
# Использование:
#   ./iam/kong/scripts/setup-kong-jwt-auth.sh
#   ./iam/kong/scripts/setup-kong-jwt-auth.sh "http://localhost:9000/application/o/<slug>/jwks/"
#   ./iam/kong/scripts/setup-kong-jwt-auth.sh --no-restart   # не перезапускать Kong после обновления конфига
# Опционально: AUTHENTIK_ACCESS_TOKEN=eyJ... — в конце проверить запрос с Bearer-токеном (ожидается ответ backend).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
KONG_YML="${REPO_ROOT}/iam/kong/kong.yml"
FETCH_SCRIPT="${SCRIPT_DIR}/fetch-authentik-jwks-pem.py"
JWKS_URL=""
NO_RESTART=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-restart) NO_RESTART=1; shift ;;
    http://*|https://*) JWKS_URL="$1"; shift ;;
    file://*) JWKS_URL="$1"; shift ;;
    *.json)
      # Локальный файл JWKS (для теста или офлайн)
      if [[ -f "$1" ]]; then
        JWKS_URL="file://$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
      else
        JWKS_URL="$1"
      fi
      shift
      ;;
    *) echo "Неизвестный аргумент: $1" >&2; exit 1 ;;
  esac
done

if [[ ! -f "$FETCH_SCRIPT" ]]; then
  echo "Ошибка: скрипт не найден: $FETCH_SCRIPT" >&2
  exit 1
fi
if [[ ! -f "$KONG_YML" ]]; then
  echo "Ошибка: файл не найден: $KONG_YML" >&2
  exit 1
fi

# Проверка зависимости (при ошибке импорта Python выведет инструкцию)
if ! python3 -c "import cryptography" 2>/dev/null; then
  echo "Установка cryptography..."
  pip install --user cryptography 2>/dev/null || pip install cryptography 2>/dev/null || {
    echo "Ошибка: установите пакет cryptography: pip install cryptography" >&2
    exit 1
  }
fi

DEFAULT_JWKS="http://localhost:9000/application/o/farmadoc_app/jwks/"
if [[ -z "$JWKS_URL" ]]; then
  JWKS_URL="$DEFAULT_JWKS"
  # Быстрая проверка: если 404 — подсказка про slug провайдера
  if ! curl -sf -o /dev/null "$JWKS_URL" 2>/dev/null; then
    echo "Предупреждение: по умолчанию запрашивается $JWKS_URL" >&2
    echo "Если провайдер создан с другим slug, укажите URL явно, например:" >&2
    echo "  $0 \"http://localhost:9000/application/o/<ваш-slug>/jwks/\"" >&2
    echo "Slug смотрите в Authentik: Directory → Providers → нужный провайдер (в URL или карточке)." >&2
  fi
fi

echo "Запрос JWKS у Authentik и обновление iam/kong/kong.yml..."
if UPDATED=$(python3 "$FETCH_SCRIPT" "$JWKS_URL" --update "$KONG_YML" 2>&1); then
  echo "Обновлён файл: $UPDATED"
else
  echo "$UPDATED" >&2
  echo "Подсказка: проверьте, что провайдер OIDC создан в Authentik и slug в URL совпадает (см. iam/docs/authentik.md)." >&2
  exit 2
fi

if [[ $NO_RESTART -eq 1 ]]; then
  echo "Kong не перезапускался (--no-restart). Перезапустите вручную: docker compose restart kong"
  exit 0
fi

if ! docker info &>/dev/null; then
  echo "Ошибка: нет доступа к Docker (permission denied)." >&2
  echo "Перезапустите Kong вручную: cd $REPO_ROOT && docker compose restart kong" >&2
  echo "Либо запустите скрипт с sudo или добавьте пользователя в группу docker." >&2
  exit 1
fi

echo "Перезапуск Kong..."
(cd "$REPO_ROOT" && docker compose restart kong)

echo "Ожидание готовности Kong (до ~35 с)..."
sleep 5
HTTP_CODE="000"
for i in {1..15}; do
  HTTP_CODE=$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 3 "http://127.0.0.1:8001/api/" 2>/dev/null || echo "000")
  [[ "${HTTP_CODE:0:3}" != "000" ]] && break
  [[ $i -lt 15 ]] && sleep 2
done
HTTP_CODE="${HTTP_CODE:0:3}"

# Если под sudo получили 000, пробуем запрос от имени пользователя (порт может быть доступен только ему)
if [[ "$HTTP_CODE" == "000" && -n "${SUDO_UID:-}" && -n "${SUDO_USER:-}" ]] && command -v runuser &>/dev/null; then
  HTTP_CODE=$(runuser -u "$SUDO_USER" -- curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 3 "http://127.0.0.1:8001/api/" 2>/dev/null || echo "000")
  HTTP_CODE="${HTTP_CODE:0:3}"
fi

echo "Проверка: запрос без токена (ожидается 401)..."
if [[ "$HTTP_CODE" == "401" ]]; then
  echo "  OK: получен 401 Unauthorized — JWT проверяется."
else
  echo "  Код ответа: ${HTTP_CODE} (ожидался 401)."
  if [[ "$HTTP_CODE" == "000" ]]; then
    echo "  Порт 8001 не отвечает (Connection refused). Диагностика Kong:"
    (cd "$REPO_ROOT" && docker compose ps kong 2>&1) | sed 's/^/    /'
    echo "  Логи Kong (--tail 25):"
    (cd "$REPO_ROOT" && docker compose logs kong --tail 25 2>&1) | sed 's/^/    /'
    echo "  Проверьте порт: curl -i http://127.0.0.1:8001/api/"
  fi
fi

if [[ -n "${AUTHENTIK_ACCESS_TOKEN:-}" ]]; then
  echo "Проверка: запрос с Bearer-токеном (ожидается ответ backend)..."
  CODE_BEARER=$(curl -si -o /dev/null -w '%{http_code}' -H "Authorization: Bearer ${AUTHENTIK_ACCESS_TOKEN}" "http://localhost:8001/api/" 2>/dev/null || echo "000")
  if [[ "$CODE_BEARER" =~ ^2[0-9][0-9]$ ]]; then
    echo "  OK: получен $CODE_BEARER — токен принят, запрос прошёл до backend."
  elif [[ "$CODE_BEARER" == "401" ]]; then
    echo "  Токен отклонён (401). Проверьте срок действия и что токен от провайдера farmadoc_app."
  else
    echo "  Код ответа: ${CODE_BEARER}"
  fi
else
  echo "Проверка с Bearer-токеном пропущена (задайте AUTHENTIK_ACCESS_TOKEN=... для проверки)."
fi
echo "Готово."
