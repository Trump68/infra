#!/bin/bash
# Создаёт БД authentik для Authentik (выполняется только при первой инициализации postgres).
# Если postgres уже был запущен ранее — создайте БД вручную:
#   docker exec postgres psql -U postgres -c "CREATE DATABASE authentik;"
set -e
if ! psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -tc "SELECT 1 FROM pg_database WHERE datname = 'authentik'" | grep -q 1; then
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -c "CREATE DATABASE authentik;"
fi
