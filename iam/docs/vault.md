# HashiCorp Vault (хранилище секретов)

Vault используется в проекте Farmadoc для хранения секретов **Authentik** (пароль PostgreSQL, секретный ключ IdP). Запуск Authentik с подстановкой секретов из Vault описан ниже.

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

Скрипты и приложения, которым нужен доступ к секретам Authentik, используют `VAULT_ADDR` и токен (`VAULT_TOKEN` или `VAULT_DEV_ROOT_TOKEN_ID` из `.env`).

## Включение KV и путь для Authentik

После запуска Vault включите хранилище KV v2 и создайте путь с секретами Authentik.

**Скрипт (только curl, Vault CLI не нужен):**

```bash
./iam/vault/scripts/setup-dev-kv.sh
```

Скрипт включает KV v2 по пути `secret/` и создаёт путь `secret/farmadoc/authentik` с ключами `postgres_password` и `secret_key` (по умолчанию — значения-заглушки). Чтобы сразу записать в Vault секреты из `.env`, запустите с параметром **`--write-from-env`** (шаг 2 по сценарию ниже):

```bash
./iam/vault/scripts/setup-dev-kv.sh --write-from-env
```

**Путь в проекте:**

| Путь | Назначение |
|------|------------|
| `secret/farmadoc/authentik` | Секреты Authentik: `postgres_password` (PG_PASS), `secret_key` (AUTHENTIK_SECRET_KEY). |

### Как посмотреть секреты в Vault

**Через HTTP API (curl, Vault CLI не нужен):**

```bash
# Все поля секрета (нужен jq для удобного вывода)
curl -s -H "X-Vault-Token: $VAULT_TOKEN" http://localhost:8200/v1/secret/data/farmadoc/authentik | jq

# Только пароль PostgreSQL
curl -s -H "X-Vault-Token: $VAULT_TOKEN" http://localhost:8200/v1/secret/data/farmadoc/authentik | jq -r '.data.data.postgres_password'

# Только секретный ключ Authentik
curl -s -H "X-Vault-Token: $VAULT_TOKEN" http://localhost:8200/v1/secret/data/farmadoc/authentik | jq -r '.data.data.secret_key'
```

Переменные `VAULT_ADDR` и `VAULT_TOKEN` (или `VAULT_DEV_ROOT_TOKEN_ID`) задайте в `.env` или в окружении. Если не заданы: `VAULT_TOKEN=dev-root-token` и адрес `http://localhost:8200`.

**Через Vault CLI** (если установлен):

```bash
export VAULT_ADDR=http://localhost:8200
export VAULT_TOKEN=dev-root-token
vault kv get secret/farmadoc/authentik
vault kv get -field=postgres_password secret/farmadoc/authentik
```

**Через UI:** откройте http://localhost:8200, войдите с токеном из `.env` (`VAULT_DEV_ROOT_TOKEN_ID`), перейдите в **Secrets** → **secret** → **farmadoc/authentik**.

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

В `.env` должны быть заданы `PG_PASS`, `AUTHENTIK_SECRET_KEY`, а также `VAULT_ADDR` и `VAULT_DEV_ROOT_TOKEN_ID` (или `VAULT_TOKEN`). Записать секреты из `.env` в Vault одной командой:

```bash
./iam/vault/scripts/setup-dev-kv.sh --write-from-env
```

Скрипт прочитает `PG_PASS` и `AUTHENTIK_SECRET_KEY` из `.env` и запишет их в `secret/farmadoc/authentik`. Если этих переменных ещё нет в `.env` (первая настройка или ротация), можно сгенерировать случайные значения: `openssl rand -base64 36 | tr -d '\n'` — для пароля БД, `openssl rand -base64 60 | tr -d '\n'` — для секретного ключа Authentik; затем добавить их в `.env` и снова выполнить команду выше.

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

### Получение кредов из Vault: варианты и выбор

Возможны два подхода к тому, как приложение (например, Authentik) получает секреты из Vault.

**Вариант 1: Запрос кредов при старте контейнера (entrypoint).**  
В образ добавляют скрипт, который перед запуском основного процесса запрашивает секрет в Vault по API, подставляет значения в переменные окружения (или во временный файл) и затем запускает приложение. Контейнеру при этом нужны `VAULT_ADDR` и `VAULT_TOKEN` (или другой токен) в окружении. Плюс: секреты можно не писать на диск хоста, а только в память процесса. Минусы: каждый контейнер должен иметь доступ к Vault (токен в env или в файле); при компрометации контейнера злоумышленник получает токен и может читать из Vault по политикам; в Docker Compose токен чаще всего передаётся из того же `.env`, то есть ещё один долгоживущий секрет в окружении контейнера.

**Вариант 2: Подготовка кредов перед запуском стека (текущая схема).**  
Перед `docker compose up` выполняется скрипт (`run-authentik-with-vault.sh`), который один раз запрашивает Vault, записывает `PG_PASS` и `AUTHENTIK_SECRET_KEY` в файл `.env.vault`, после чего контейнеры поднимаются с `env_file: .env.vault`. Контейнеры не получают `VAULT_TOKEN` и не обращаются к Vault — только к переменным окружения с двумя нужными секретами.

**Почему в проекте выбран вариант 2:**

1. **Минимальные привилегии:** контейнеры не имеют доступа к Vault и не могут по токену запрашивать другие секреты. При компрометации контейнера утечка ограничена только теми креды, которые ему нужны.
2. **Токен Vault не попадает в контейнеры:** его знает только хост (или CI), на котором выполняется скрипт. Меньше мест хранения и использования токена — меньше поверхность атаки.
3. **Ограничение последствий взлома:** скомпрометированный контейнер не может использовать Vault для доступа к остальным секретам в хранилище.

Минус варианта 2 — появление файла `.env.vault` на диске хоста. Его можно смягчить: держать файл вне репозитория (он в `.gitignore`), выставить права `chmod 600 .env.vault`, а токен для доступа к Vault на проде хранить в секрет-менеджере или переменных CI, а не в общем `.env`.

Вариант 1 оправдан, когда есть инфраструктура для короткоживущих токенов (например, Kubernetes + Vault Agent / CSI) и жёсткое требование не писать секреты на диск. В типичном Docker Compose без этого вариант 2 даёт лучший баланс безопасности и простоты.

---

### Требования и примечания

- **Путь в Vault:** `secret/farmadoc/authentik`, ключи `postgres_password` и `secret_key`.
- **Переменные для доступа к Vault:** `VAULT_ADDR` (по умолчанию `http://localhost:8200`), `VAULT_TOKEN` или `VAULT_DEV_ROOT_TOKEN_ID` — из `.env` или окружения.
- Файл `.env.vault` создаётся в корне репозитория, добавлен в `.gitignore`; не коммитить.
- Остальные переменные Authentik (`PG_USER`, `PG_DB` и т.д.) задаются в `.env` при необходимости.

### Ротация секретов

Последовательность при смене `postgres_password` или `secret_key`:

1. **Обновить значение в Vault** — записать новые данные в `secret/farmadoc/authentik`.
2. **Обновить `.env.vault` из Vault** (без запуска контейнеров):  
   `./iam/authentik/scripts/run-authentik-with-vault.sh --prepare-only`
3. **Перезапустить Authentik**, чтобы контейнеры подхватили обновлённый `.env.vault`:  
   `docker compose restart authentik-server authentik-worker`  
   (при смене пароля БД может понадобиться также перезапуск `authentik-postgresql` или смена пароля в PostgreSQL — см. ниже).

**Как обновить секрет в Vault:**

- **Через .env:** задайте новые `PG_PASS` и/или `AUTHENTIK_SECRET_KEY` в `.env`, затем выполните  
  `./iam/vault/scripts/setup-dev-kv.sh --write-from-env` — в Vault запишется содержимое из `.env`.
- **Напрямую:** обновите секрет через API (curl) или UI (Secrets → secret → farmadoc/authentik), как при первичной записи.

**Ротация пароля PostgreSQL (`postgres_password`):** если меняете пароль БД, сначала смените его в самой PostgreSQL (например, `ALTER USER authentik PASSWORD 'новый_пароль';` или пересоздайте пользователя), затем обновите значение в Vault и выполните шаги 2–3 выше. Иначе Authentik получит новый пароль из Vault, а в БД останется старый — подключение будет падать.

Автоматического расписания ротации (cron и т.п.) в репозитории нет; периодичность задаётся при необходимости отдельно.

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
