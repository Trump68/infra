# Authentik (OAuth2/OIDC)

Authentik — сервер авторизации (IdP) для единого входа в стеке Farmadoc. Выдаёт токены браузерному приложению; Kong проверяет их по OpenID Connect. Использует отдельную БД `authentik` на том же экземпляре PostgreSQL, что и остальные сервисы.

**Текущий этап:** доступ по HTTP на localhost и указанных портах; TLS и домены настраиваются при необходимости отдельно.

---

## Предварительные требования

- **Docker** и **Docker Compose** (v2)
- Репозиторий с файлами: `docker-compose.yml`, `postgres/init-authentik-db.sh`, `authentik/blueprints/farmadoc-oidc.yaml`, `authentik/scripts/apply-farmadoc-blueprint.sh`
- Для скрипта применения blueprint: `curl`, а также `jq` или `python3`

---

## Полный цикл установки (bootstrap + скрипт)

Цель: от нуля до работающего Authentik с провайдером Farmadoc OIDC и приложением **farmadoc_client** без ручного создания провайдера в UI.

**Минимальный путь:** подготовить `.env` (шаг 1) и один раз запустить скрипт применения blueprint (шаг 4). Скрипт сам выполнит шаги 2 и 3 (БД, запуск сервисов, ожидание API). Шаги 2 и 3 ниже — для ручного варианта или справки.

### 1. Подготовка .env

В корне репозитория:

```bash
cp .env.example .env
```

Задайте в `.env`:

| Переменная | Назначение |
|------------|------------|
| `AUTHENTIK_SECRET_KEY` | Случайная строка, например: `openssl rand -base64 48` |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` | Учётные данные PostgreSQL (Authentik использует ту же инстанцию, БД `authentik`). По умолчанию в `.env.example`: `postgres` / `postgres`. |
| `POSTGRES_DB` | (опционально) Имя основной БД postgres, по умолчанию `postgres`. БД `authentik` создаётся отдельно. |
| `AUTHENTIK_BOOTSTRAP_TOKEN` | Значение станет первым API-токеном для akadmin; сгенерируйте: `openssl rand -base64 32` |
| `AUTHENTIK_BOOTSTRAP_PASSWORD` | Пароль пользователя akadmin (при первом запуске создаётся аккаунт с этим паролем) |
| `AUTHENTIK_BOOTSTRAP_EMAIL` | (опционально) Email для akadmin, например `admin@localhost` |

Без bootstrap переменные `AUTHENTIK_BOOTSTRAP_*` можно не задавать; тогда после первого запуска потребуется ручной initial-setup в браузере и создание токена в **System → Tokens**.

### 2. БД authentik (если не используете скрипт шага 4)

- **Первый запуск postgres (чистый volume):** при монтировании `postgres/init-authentik-db.sh` в `docker-compose.yml` (каталог `docker-entrypoint-initdb.d`) БД `authentik` создаётся при инициализации контейнера.
- **PostgreSQL уже использовался ранее:** создайте БД вручную до первого запуска authentik-server/worker:

```bash
docker compose up -d postgres
docker exec postgres psql -U postgres -c "CREATE DATABASE authentik;"
```

(При другом пользователе: `-U $POSTGRES_USER`, при другой БД: `-d $POSTGRES_DB`.)

### 3. Запуск сервисов (если не используете скрипт шага 4)

```bash
docker compose up -d postgres redis authentik-server authentik-worker
```

Дождитесь готовности (миграции при первом запуске — 1–3 минуты). Проверка: `docker compose logs -f authentik-server`.

Вход в панель: `http://localhost:9000`. При успешном bootstrap — **akadmin** и пароль из `AUTHENTIK_BOOTSTRAP_PASSWORD`. Если bootstrap не сработал (см. раздел «API-токен»), откройте `http://localhost:9000/if/flow/initial-setup/` и задайте пароль суперадмина один раз.

### 4. Применение blueprint (рекомендуемый способ — один скрипт на шаги 2–4)

Скрипт **`authentik/scripts/apply-farmadoc-blueprint.sh`** выполняет шаги 2–4 целиком: запускает PostgreSQL при необходимости, создаёт БД `authentik` при отсутствии, поднимает Redis и Authentik (server, worker), ждёт готовности API и применяет blueprint. Запуск из **корня репозитория** (нужен подготовленный `.env`, шаг 1):

```bash
./authentik/scripts/apply-farmadoc-blueprint.sh
```

Скрипт подхватывает `.env` из корня репозитория; по умолчанию `AUTHENTIK_URL=http://localhost:9000`. Токен берётся из `AUTHENTIK_TOKEN` или `AUTHENTIK_BOOTSTRAP_TOKEN`. URL и токен можно передать аргументами:

```bash
./authentik/scripts/apply-farmadoc-blueprint.sh http://localhost:9000 ваш-токен
```

Если Authentik уже запущен и нужно только применить blueprint (без шагов 2–3):

```bash
SKIP_DOCKER_SETUP=1 ./authentik/scripts/apply-farmadoc-blueprint.sh
```

Ожидание API по умолчанию: до 60 попыток каждые 2 с. Задать свои значения: `AUTHENTIK_WAIT_ATTEMPTS=90` и/или `AUTHENTIK_WAIT_DELAY=3`.

При успехе в **Directory → Providers** и **Directory → Applications** появятся провайдер **Farmadoc OIDC** и приложение **farmadoc_client**.

### 5. Интеграция с Kong и SPA

- В **kong/kong.yml** в плагине OpenID Connect укажите `issuer` для созданного провайдера (slug из blueprint — `farmadoc-oidc`):  
  `http://authentik-server:9000/application/o/farmadoc-oidc/.well-known/openid-configuration/`
- Запуск при необходимости: `docker compose up -d backend kong`
- В SPA настройте OAuth2/OIDC с тем же issuer; redirect URI из blueprint по умолчанию: `http://localhost:3000/callback`. Изменения — в `authentik/blueprints/farmadoc-oidc.yaml` и повторное применение blueprint или правка провайдера в UI.

---

## Переменные окружения (справочник)

**Обязательные для запуска:** `AUTHENTIK_SECRET_KEY`, `POSTGRES_USER`, `POSTGRES_PASSWORD` (значения по умолчанию — в `.env.example`).

**Опционально (bootstrap):** `AUTHENTIK_BOOTSTRAP_TOKEN`, `AUTHENTIK_BOOTSTRAP_PASSWORD`, `AUTHENTIK_BOOTSTRAP_EMAIL` — передаются в контейнеры authentik-server и authentik-worker через `docker-compose.yml`.

**Опционально (скрипт apply-farmadoc-blueprint.sh):** `AUTHENTIK_WAIT_ATTEMPTS` (по умолчанию 60), `AUTHENTIK_WAIT_DELAY` (с, по умолчанию 2) — число попыток и интервал при ожидании готовности API. `POSTGRES_DB` — основная БД postgres (по умолчанию `postgres`), используется скриптом для проверки/создания БД `authentik`.

---

## API-токен

Нужен для скрипта применения blueprint и для вызовов REST API.

**Получение вручную:** панель Authentik → **System** → **Tokens** → **Create** → укажите Identifier (например `blueprint-apply`), при необходимости права (для blueprint — права на blueprints или полные) → **Create**. Токен показывается один раз — сохраните в `AUTHENTIK_TOKEN` или передайте в скрипт.

**Bootstrap:** при первом запуске можно задать `AUTHENTIK_BOOTSTRAP_TOKEN` и `AUTHENTIK_BOOTSTRAP_PASSWORD` в `.env` — тогда при инициализации создаётся аккаунт akadmin и токен, равный `AUTHENTIK_BOOTSTRAP_TOKEN`. Его можно использовать в скрипте (скрипт подставляет `AUTHENTIK_BOOTSTRAP_TOKEN`, если `AUTHENTIK_TOKEN` не задан).

**Ограничение:** в части версий Authentik (2023.8+) bootstrap не срабатывает при «чистом» первом запуске ([issue #7546](https://github.com/goauthentik/authentik/issues/7546)). Тогда после шага 3 выполните initial-setup в браузере и создайте токен в **System → Tokens**, затем используйте его в шаге 4.

### Если bootstrap не создал токен

Если скрипт `apply-farmadoc-blueprint.sh` выдаёт **403 "Token invalid/expired"**, значит токен из `AUTHENTIK_BOOTSTRAP_TOKEN` в этой установке не был создан (bootstrap не сработал или БД пересоздавалась). Сделайте следующее:

1. **Первый вход (если ещё не делали):** откройте `http://localhost:9000/if/flow/initial-setup/` и задайте пароль для пользователя **akadmin**.
2. **Войдите в панель:** `http://localhost:9000` — логин **akadmin**, пароль из шага 1 (или из `AUTHENTIK_BOOTSTRAP_PASSWORD`, если задавали).
3. **Создайте API-токен:** **System** → **Tokens** → **Create** → укажите Identifier (например `blueprint-apply`) → **Create** → скопируйте выданный токен (показывается один раз).
4. **Примените blueprint с этим токеном** (сервисы уже запущены, шаги 2–3 скрипта пропускаем):
   ```bash
   SKIP_DOCKER_SETUP=1 ./authentik/scripts/apply-farmadoc-blueprint.sh http://localhost:9000 'ваш-скопированный-токен'
   ```
   Либо добавьте в `.env`: `AUTHENTIK_TOKEN=ваш-токен` и выполните:
   ```bash
   SKIP_DOCKER_SETUP=1 ./authentik/scripts/apply-farmadoc-blueprint.sh
   ```

После этого провайдер и приложение появятся в **Directory → Providers** и **Directory → Applications**.

---

## Интеграция с Kong (issuer)

Kong проверяет JWT по OpenID Connect: сверяет подпись и утверждение `iss` с данными Authentik. Параметр **issuer** в конфиге Kong — URL документа **OpenID Connect Discovery** провайдера.

**Формат:**

```
http://authentik-server:9000/application/o/<slug>/.well-known/openid-configuration/
```

`<slug>` — идентификатор провайдера в Authentik (у провайдера, не у приложения). Для blueprint Farmadoc slug — `farmadoc-oidc`. Хост `authentik-server:9000` — из сети Docker (Kong и Authentik в одной сети).

**Где править:** `kong/kong.yml`, блок плагина `openid-connect`, поле `config.issuer`. После изменений: `docker compose up -d kong` или `docker compose restart kong`.

**Проверка:** откройте URL issuer в браузере (с хоста: `http://localhost:9000/application/o/<slug>/.well-known/openid-configuration/`) — должен вернуться JSON с `issuer`, `jwks_uri`, `authorization_endpoint` и др. Запрос к `http://localhost:8001/api/...` без токена — 401; с валидным Bearer-токеном от Authentik — ответ от backend.

Подробнее: [kong.md](../../docs/kong.md).

---

## Доступ и остановка

- **С хоста:** `http://localhost:9000`. С другого ПК — `http://<IP-хоста>:9000` или SSH-туннель: `ssh -L 9000:localhost:9000 user@remote-host` (если порт 9000 занят локально — другой порт, например `-L 9001:localhost:9000`, тогда `http://localhost:9001`). Порт 9443 — для HTTPS при настройке TLS.
- **Из контейнеров** в сети `farmadoc-network`: `http://authentik-server:9000`.

**Остановка:**

```bash
docker compose stop authentik-server authentik-worker
```

**Полное удаление** (контейнеры, БД `authentik`, тома `authentik_media` и `authentik_templates`): из корня репозитория выполните `./authentik/scripts/uninstall-authentik.sh`. Запрос подтверждения можно пропустить флагом `-f` или `--force`. Kong зависит от authentik-server — после удаления Authentik Kong нужно остановить или изменить конфиг.

Данные: БД `authentik` на том же PostgreSQL (volume `postgres_data`), плюс volume `authentik_media`, `authentik_templates`.

---

## Ручная настройка OIDC в UI

Если вы не используете blueprint и создаёте провайдер и приложение вручную.

### Создание провайдера (OpenID Connect Provider)

**Directory** → **Providers** → **Create** → **OpenID Connect Provider**.

| Экран / поле | Рекомендация |
|--------------|--------------|
| **Тип** | OpenID Connect Provider (OAuth2/OIDC) |
| **Имя** | Произвольное (например Farmadoc). От имени может зависеть **slug** в URL для Kong. |
| **Поток аутентификации** | default-authentication-flow (Welcome to authentik!) |
| **Поток авторизации** | default-provider-authorization-explicit-consent (Authorize Application). Не использовать implicit-consent. |
| **Тип клиента** | Публичный (Public) для SPA; конфиденциальный — только если с Authentik общается только backend с client secret. |
| **Перенаправляющие URI** | Точный URL возврата после входа, например `http://localhost:3000/callback`. Несколько — с новой строки. Не использовать `.*` в продакшене. |
| **Подписывающий ключ** | authentik Self-signed Certificate |
| **Срок кода доступа** | minutes=1 |
| **Срок Access токена** | hours=1 или minutes=30 для разработки |
| **Срок Refresh токена** | days=30 (или по необходимости) |
| **Scopes** | Минимум openid; рекомендуется email, profile. |
| **Режим субъекта (Subject)** | Хэшированный идентификатор пользователя (рекомендуется). |
| **Утверждения в id_token** | Включено. Режим эмитента: «У каждого провайдера свой эмитент» (issuer по slug). |
| **Доверенные источники OIDC** | Пусто, если пользователи только локальные в Authentik. |

После сохранения запомните **slug** провайдера — он нужен для Kong (issuer) и для приложения.

### Создание приложения (Application)

**Applications** → **Create**. Имя и идентификатор (slug) — например `farmadoc_client`. **Провайдер** — выберите созданный OAuth2/OIDC провайдер. **Режим механизма политики** — any. Redirect URIs и параметры OAuth2 задаются в настройках провайдера, не приложения.

---

## Автоматизация: Blueprint и API

Готовый blueprint **`authentik/blueprints/farmadoc-oidc.yaml`** создаёт провайдер «Farmadoc OIDC» и приложение «farmadoc_client» (публичный клиент, explicit consent, redirect `http://localhost:3000/callback`, scopes openid/email/profile). Перед применением нужен выполненный initial-setup и наличие потоков по умолчанию и ключа «authentik Self-signed Certificate».

**Способы применения:**

1. **Веб:** **Customization** → **Blueprints** → **Apply blueprint** → загрузить файл `authentik/blueprints/farmadoc-oidc.yaml`.
2. **Скрипт (рекомендуется):** из корня репозитория — `./authentik/scripts/apply-farmadoc-blueprint.sh` с заданными `AUTHENTIK_URL` и `AUTHENTIK_TOKEN` (или `AUTHENTIK_BOOTSTRAP_TOKEN`). Скрипт пробует несколько вариантов API и применяет blueprint при первом успешном.
3. **API вручную:** токен в **System → Tokens**; эндпоинты и схема — `http://localhost:9000/api/v3/schema/swagger/`. Порядок: создать managed blueprint с содержимым YAML, затем вызвать apply для созданного экземпляра.

**Изменение redirect URI:** отредактируйте массив `redirect_uris` в `farmadoc-oidc.yaml` и примените blueprint заново или измените провайдер в UI.

| Способ | Плюсы | Минусы |
|--------|--------|--------|
| UI (ручная настройка) | Понятно, все поля под рукой | Долго, не воспроизводимо |
| Blueprint (YAML + скрипт) | Версионирование, повторяемость | Нужны slug потоков и структура YAML |
| REST API вручную | Гибкая автоматизация | Нужен токен и знание схемы API |

---

## Устранение неполадок

| Симптом | Действие |
|--------|----------|
| В браузере «failed to connect to authentik backend: authentik starting» | Сервер ещё поднимается (миграции 1–3 мин). Подождите, обновите страницу. Логи: `docker compose logs -f authentik-server`. |
| В логах «database \"authentik\" does not exist» | БД не создана (postgres был запущен до добавления init-скрипта). Создайте БД: `docker exec postgres psql -U postgres -d postgres -c "CREATE DATABASE authentik;"` (при другом пользователе: `-U $POSTGRES_USER`), затем `docker compose restart authentik-server authentik-worker`. |
| Скрипт apply-farmadoc-blueprint.sh: «Authentik API не ответил за отведённое время» | Увеличьте ожидание: `AUTHENTIK_WAIT_ATTEMPTS=90 AUTHENTIK_WAIT_DELAY=3 ./authentik/scripts/apply-farmadoc-blueprint.sh`. Проверьте логи: `docker compose logs -f authentik-server`. |
| Скрипт: «Token invalid/expired» или HTTP 401/403 | Bootstrap не создал токен в этой установке. Пошагово: раздел [Если bootstrap не создал токен](#если-bootstrap-не-создал-токен) выше — initial-setup, вход в панель, создание токена в **System** → **Tokens**, затем запуск скрипта с `SKIP_DOCKER_SETUP=1` и новым токеном. |
| Скрипт: HTTP 405 при применении blueprint | В части версий Authentik API managed blueprints возвращает 405 на POST с полным телом. Обходной путь: примените blueprint вручную — **Customization** → **Blueprints** → **Apply blueprint** → загрузите файл `authentik/blueprints/farmadoc-oidc.yaml`. |
| Bootstrap не создал токен / не задал пароль | Выполните initial-setup: `http://localhost:9000/if/flow/initial-setup/`, затем **System** → **Tokens** → Create и сохраните токен. См. также [Если bootstrap не создал токен](#если-bootstrap-не-создал-токен). |
| Порт 9000 занят при SSH-туннеле | Используйте другой локальный порт: `ssh -L 9001:localhost:9000 user@remote-host`, затем `http://localhost:9001` (и при вызове скрипта: `AUTHENTIK_URL=http://localhost:9001`). |

---

## См. также

- [kong.md](../../docs/kong.md) — API Gateway, плагин OpenID Connect
- [auth-flow.md](../../docs/auth-flow.md) — схема OAuth2/OIDC: приложение → Authentik → Kong → backend
