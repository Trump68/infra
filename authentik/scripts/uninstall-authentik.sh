#!/usr/bin/env bash
# Полное удаление установленного Authentik: контейнеры, БД authentik, тома.
# Запуск из корня репозитория: ./authentik/scripts/uninstall-authentik.sh
# Опция: -f | --force — без подтверждения.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "$REPO_ROOT"

# Проверка доступа к Docker (без прав будет permission denied на одном из шагов)
if ! docker info &>/dev/null; then
  echo "Ошибка: нет доступа к Docker (permission denied)." >&2
  echo "Запустите скрипт с sudo: sudo $0 $*" >&2
  echo "Либо добавьте пользователя в группу docker: sudo usermod -aG docker \$USER и перелогиньтесь." >&2
  exit 1
fi

FORCE=
for arg in "$@"; do
  case "$arg" in
    -f|--force) FORCE=1 ;;
  esac
done

if [[ -z "$FORCE" ]]; then
  echo "Будет выполнено:"
  echo "  1. Остановка и удаление контейнеров authentik-server, authentik-worker"
  echo "  2. Удаление БД 'authentik' в PostgreSQL (контейнер postgres должен быть запущен)"
  echo "  3. Удаление томов authentik_media, authentik_templates"
  echo ""
  echo "Kong зависит от authentik-server: после удаления Authentik Kong не сможет проверять JWT; при необходимости остановите Kong или измените конфиг."
  echo ""
  read -r -p "Продолжить? [y/N] " ans
  if [[ ! "$ans" =~ ^[yY] ]]; then
    echo "Отменено."
    exit 0
  fi
fi

echo "[1/4] Остановка authentik-server и authentik-worker..."
docker compose stop authentik-server authentik-worker 2>/dev/null || true

echo "[2/4] Удаление контейнеров..."
docker rm -f authentik-server authentik-worker 2>/dev/null || true

echo "[3/4] Удаление БД authentik в PostgreSQL..."
# POSTGRES_USER из .env или по умолчанию postgres
if [[ -f .env ]]; then
  set -a
  # shellcheck source=/dev/null
  source .env
  set +a
fi
POSTGRES_USER="${POSTGRES_USER:-postgres}"
if docker exec postgres psql -U "$POSTGRES_USER" -d postgres -c "DROP DATABASE IF EXISTS authentik;" 2>/dev/null; then
  :
else
  echo "Предупреждение: не удалось удалить БД authentik (контейнер postgres не запущен или нет прав). Запустите: docker compose up -d postgres , затем выполните: docker exec postgres psql -U $POSTGRES_USER -d postgres -c \"DROP DATABASE IF EXISTS authentik;\"" >&2
fi

echo "[4/4] Удаление томов authentik_media, authentik_templates..."
for vol in $(docker volume ls -q | grep -E '_authentik_media$|_authentik_templates$'); do
  docker volume rm "$vol" 2>/dev/null || echo "Предупреждение: не удалось удалить том $vol (возможно, используется)" >&2
done

echo "Готово. Authentik удалён. Для повторной установки выполните полный цикл из authentik/doc/authentik.md."
