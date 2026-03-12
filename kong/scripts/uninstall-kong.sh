#!/usr/bin/env bash
# Полное удаление Kong: остановка и удаление контейнера kong.
# Запуск из корня репозитория: ./kong/scripts/uninstall-kong.sh
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
  echo "  1. Остановка и удаление контейнера kong"
  echo ""
  echo "Конфиг kong/kong.yml на хосте не удаляется. Зависимости (authentik-server, backend) не трогаются."
  echo ""
  read -r -p "Продолжить? [y/N] " ans
  if [[ ! "$ans" =~ ^[yY] ]]; then
    echo "Отменено."
    exit 0
  fi
fi

echo "[1/1] Остановка и удаление контейнера kong..."
docker compose stop kong 2>/dev/null || true
docker rm -f kong 2>/dev/null || true

echo "Готово. Kong удалён. Для повторной установки: docker compose up -d kong (см. kong/kong.yml и документацию)."
