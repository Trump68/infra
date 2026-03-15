# HashiCorp Vault (хранилище секретов)

Vault используется в проекте Farmadoc для хранения секретов и ключей шифрования в соответствии с ТЗ и Описанием ПО: раздел 3.5.3 — ключи шифрования векторной БД (AES-256 / ГОСТ), ротация каждые 90 дней; раздел 4.3 — внешние компоненты. При интеграции здесь же можно хранить секреты приложений (Authentik, PostgreSQL и т.д.).

## Запуск (Docker Compose)

Из корня репозитория:

```bash
docker compose up -d vault
```

Проверка:

```bash
curl -s http://localhost:8200/v1/sys/health
```

Порт **8200** — API и UI. С хоста: **http://localhost:8200**. Из контейнеров в сети `farmadoc-network`: **http://vault:8200**. Для входа в UI используйте токен из `.env` — `VAULT_DEV_ROOT_TOKEN_ID`.

## Режим работы

- **Текущая конфигурация (dev):** Vault запущен в **dev-режиме** — один узел, хранилище в памяти, автоматически unseal, один root-токен из переменной `VAULT_DEV_ROOT_TOKEN_ID` в `.env`. Подходит только для разработки и тестов. При перезапуске контейнера все данные теряются.
- **Продакшен:** для боевого окружения разверните Vault в [production mode](https://developer.hashicorp.com/vault/docs/concepts/seal): файловое или иное хранилище, несколько узлов при необходимости, процедура unseal (ключи разделения). Конфигурация выносится в отдельный файл (см. пример [iam/vault/config.hcl.example](../vault/config.hcl.example)) и монтируется в контейнер.

## Переменные окружения

| Переменная | По умолчанию | Описание |
|------------|--------------|----------|
| `VAULT_ADDR` | `http://localhost:8200` | URL Vault. С хоста — localhost:8200; из контейнеров в сети — `http://vault:8200`. |
| `VAULT_DEV_ROOT_TOKEN_ID` | `dev-root-token` | Root-токен в dev-режиме (в проде не используется; вместо него — выдача токенов или AppRole). |

Клиенты (backend, скрипты) должны иметь `VAULT_ADDR` и токен (через `VAULT_TOKEN` или переменную окружения приложения). Сервисы, которым нужен доступ к секретам (например, модуль работы с векторной БД), получают их через конфигурацию/окружение.

## Включение KV и пример путей секретов

После запуска включите секретное хранилище KV v2 и при необходимости создайте пример секрета.

**Вариант 1 — скрипт (нужен [Vault CLI](https://developer.hashicorp.com/vault/docs/install) на хосте):**

```bash
./iam/vault/scripts/setup-dev-kv.sh
```

**Вариант 2 — команды с хоста (Vault CLI установлен):**

```bash
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=dev-root-token   # или значение из VAULT_DEV_ROOT_TOKEN_ID в .env

vault secrets enable -path=secret kv-v2
vault kv put secret/farmadoc/vector-db encryption_key="CHANGE-ME" key_id="current"
vault kv get secret/farmadoc/vector-db
```

**Вариант 3 — без Vault CLI (команды внутри контейнера):**

```bash
docker compose exec vault vault secrets enable -path=secret kv-v2
docker compose exec vault vault kv put secret/farmadoc/vector-db encryption_key="CHANGE-ME" key_id="current"
docker compose exec vault vault kv get secret/farmadoc/vector-db
```

Рекомендуемые пути в проекте:

| Путь | Назначение |
|------|------------|
| `secret/farmadoc/vector-db` | Ключи шифрования векторной БД (Описание ПО, п. 3.5.3). |
| `secret/farmadoc/postgres` | Учётные данные PostgreSQL (при использовании Vault для БД). |
| `secret/farmadoc/authentik` | Секреты Authentik: `postgres_password` (PG_PASS), `secret_key` (AUTHENTIK_SECRET_KEY). |

---

## Как запускать Authentik с секретами из Vault

Один скрипт: **`iam/authentik/scripts/run-authentik-with-vault.sh`**. Он создаёт файл `.env.vault` (из Vault или из `.env`) и при необходимости запускает контейнеры; есть режим `--env-only` (секреты только в окружении, без `.env.vault`). Все команды выполняются из **корня репозитория**.

### Вариант A: Секреты хранятся в Vault

**Шаг 1. Запустить Vault и включить KV v2** (один раз):

```bash
docker compose up -d vault
./iam/vault/scripts/setup-dev-kv.sh
```

**Шаг 2. Записать секреты Authentik в Vault** (один раз или при ротации):

В `.env` должны быть заданы `VAULT_ADDR` и `VAULT_DEV_ROOT_TOKEN_ID` (или `VAULT_TOKEN`). Затем:

```bash
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=dev-root-token   # или из .env

vault kv put secret/farmadoc/authentik \
  postgres_password='ваш_пароль_postgres' \
  secret_key='ваш_authentik_secret_key'
```

Сгенерировать значения: `openssl rand -base64 36 | tr -d '\n'` (пароль), `openssl rand -base64 60 | tr -d '\n'` (secret_key). Или взять из текущего `.env` и перенести в Vault.

**Шаг 3. Запустить Authentik** (секреты подставятся из Vault в `.env.vault`, затем поднимутся контейнеры):

```bash
./iam/authentik/scripts/run-authentik-with-vault.sh
```

Скрипт читает из Vault `secret/farmadoc/authentik`, записывает `PG_PASS` и `AUTHENTIK_SECRET_KEY` в `.env.vault` и выполняет `docker compose up -d authentik-postgresql authentik-redis authentik-server authentik-worker`.

---

### Вариант B: Секреты только в .env (без Vault)

Если Vault не используется, секреты остаются в `.env`. Создать `.env.vault` из них и запустить Authentik одной командой:

```bash
./iam/authentik/scripts/run-authentik-with-vault.sh --from-env
```

Скрипт скопирует `PG_PASS` и `AUTHENTIK_SECRET_KEY` из `.env` в `.env.vault` и поднимет контейнеры Authentik.

---

### Только подготовить .env.vault (без запуска контейнеров)

Если нужно только создать или обновить `.env.vault`, а `docker compose up` выполнить отдельно или позже:

```bash
./iam/authentik/scripts/run-authentik-with-vault.sh --prepare-only              # из Vault
./iam/authentik/scripts/run-authentik-with-vault.sh --prepare-only --from-env   # из .env
```

После этого запуск Authentik — обычной командой:  
`docker compose up -d authentik-postgresql authentik-redis authentik-server authentik-worker`.

---

### Вариант C: Секреты только в окружении (без файла .env.vault)

Секреты подставляются в переменные окружения процесса, файл `.env.vault` не создаётся. Удобно, если нужно передать свои аргументы в `docker compose` (например, поднять не только Authentik):

```bash
./iam/authentik/scripts/run-authentik-with-vault.sh --env-only up -d authentik-postgresql authentik-redis authentik-server authentik-worker
./iam/authentik/scripts/run-authentik-with-vault.sh --env-only --from-env up -d   # секреты из .env, поднять весь стек
```

---

### Требования и примечания

- **Путь в Vault:** `secret/farmadoc/authentik`, ключи `postgres_password` и `secret_key`.
- **Переменные для доступа к Vault:** `VAULT_ADDR` (по умолчанию `http://localhost:8200`), `VAULT_TOKEN` или `VAULT_DEV_ROOT_TOKEN_ID` — из `.env` или окружения.
- Файл `.env.vault` создаётся в корне репозитория, добавлен в `.gitignore`; не коммитить.
- Остальные переменные Authentik (`PG_USER`, `PG_DB` и т.д.) задаются в `.env` при необходимости.

Ротация ключей (90 дней): обновить секрет в Vault, при необходимости выполнить `run-authentik-with-vault.sh --prepare-only` и перезапустить контейнеры Authentik.

## Доступ из контейнеров

Сервисы в сети `farmadoc-network` обращаются к Vault по адресу **http://vault:8200**. Передайте в контейнер переменные:

- `VAULT_ADDR=http://vault:8200`
- `VAULT_TOKEN=...` (или используйте AppRole / другой механизм в проде)

## Остановка

```bash
docker compose stop vault
```

## Связанные документы

- [authentik.md](authentik.md) — IdP (секреты Authentik при необходимости можно хранить в Vault).
- [kong.md](kong.md) — API Gateway (секреты при необходимости — в Vault).
- Конфигурация и скрипты Vault: [iam/vault/](../vault/) (config.hcl.example, scripts/).
- [HashiCorp Vault: Developer Quick Start](https://developer.hashicorp.com/vault/docs/get-started/developer-qs).
- [Vault KV v2](https://developer.hashicorp.com/vault/docs/secrets/kv/kv-v2).
