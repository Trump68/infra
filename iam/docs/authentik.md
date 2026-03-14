# Authentik (OAuth2/OIDC)

Authentik — сервер авторизации (IdP) для единого входа в стеке Farmadoc. Выдаёт токены браузерному приложению (через BFF); Kong проверяет JWT по ключам из Authentik (плагин jwt + JWKS).

**Текущая конфигурация:** Authentik 2026.2 по [официальному docker-compose](https://version-2026-2.goauthentik.io/install-config/install/docker-compose/): отдельные контейнеры `authentik-postgresql`, `authentik-redis`, `authentik-server`, `authentik-worker`. Доступ по HTTP на localhost и указанных портах; TLS и домены настраиваются при необходимости отдельно.

---

## Предварительные требования

- **Docker** и **Docker Compose** (v2)
- Файлы в репозитории: `docker-compose.yml`, `iam/authentik/scripts/authentik-setup.sh`, при необходимости `iam/authentik/blueprints/farmadoc-oidc.yaml`
- Для скрипта применения blueprint: `curl`, а также `jq` или `python3`

---

## Установка Authentik 2026.2 (текущий docker-compose)

### 1. Подготовка .env

В корне репозитория:

```bash
cp .env.example .env
```

Задайте в `.env` (обязательно):

| Переменная | Назначение |
|------------|------------|
| `PG_PASS` | Пароль PostgreSQL для Authentik (до 99 символов). Сгенерировать: `openssl rand -base64 36 \| tr -d '\n'` |
| `AUTHENTIK_SECRET_KEY` | Секретный ключ Authentik. Сгенерировать: `openssl rand -base64 60 \| tr -d '\n'` |

Опционально: `PG_USER` (по умолчанию `authentik`), `PG_DB` (по умолчанию `authentik`), `COMPOSE_PORT_HTTP` / `COMPOSE_PORT_HTTPS` (9000 / 9443).

### 2. Запуск сервисов

```bash
docker compose up -d authentik-postgresql authentik-redis authentik-server authentik-worker
```

Дождитесь готовности (миграции при первом запуске — 1–3 минуты). Проверка: `docker compose logs -f authentik-server`.

### 3. Первичная настройка (один раз)

При первом запуске откройте в браузере:

**http://localhost:9000**

Пройдите мастер initial-setup: создайте учётную запись администратора (логин и пароль). После этого панель будет доступна по тому же адресу.

### 4. Провайдер и приложение

- **Вариант А (рекомендуется):** создайте провайдер OIDC и приложение вручную по чеклисту ниже — раздел [Ручная настройка OIDC в UI](#ручная-настройка-oidc-в-ui).
- **Вариант Б:** если есть blueprint `iam/authentik/blueprints/farmadoc-oidc.yaml` и API-токен, примените его: **System** → **Tokens** → Create → скопируйте токен, затем из корня репозитория:
  ```bash
  SKIP_DOCKER_SETUP=1 ./iam/authentik/scripts/authentik-setup.sh -e http://localhost:9000 'ваш-токен'
  ```
  Скрипт с `SKIP_DOCKER_SETUP=1` не трогает контейнеры и только загружает blueprint в уже запущенный Authentik.

---

## Ручная настройка OIDC в UI

Если вы не используете blueprint, создайте провайдер и приложение вручную. Ниже — чеклист с конкретными значениями для стека Farmadoc (BFF + Kong).

### Провайдер (OpenID Connect Provider)

**Directory** → **Providers** → **Create** → **OpenID Connect Provider**.

| Поле | Значение |
|------|----------|
| **Имя** | `farmadoc_public_explicit_authentication_flow` |
| **Поток аутентификации** | default-authentication-flow (Welcome to authentik!) |
| **Поток авторизации** | default-provider-authorization-explicit-consent (Authorize Application) |
| **Тип клиента** | Публичный (Public) |
| **Перенаправляющие URI** | `http://localhost:3000/callback`; при доступе по IP добавьте `http://<IP>:3000/callback` (например `http://192.168.173.157:3000/callback`) |
| **Подписывающий ключ** | authentik Self-signed Certificate |
| **Срок кода доступа** | minutes=1 |
| **Срок Access токена** | hours=1 |
| **Срок Refresh токена** | days=30 |
| **Scopes** | openid, email, profile |
| **Режим субъекта (Subject)** | Хэшированный идентификатор пользователя |
| **Утверждения в id_token** | Включено |
| **Режим эмитента (Issuer)** | У каждого провайдера свой эмитент (per provider) |

После сохранения проверьте **slug** приложения (у провайдера/приложения). Для приложения с slug `farmadoc_app` или `farmadoc-app`:

- **Discovery (OIDC):** `http://localhost:9000/application/o/<slug>/.well-known/openid-configuration` (для BFF/клиента)
- **JWKS (для Kong JWT):** `http://localhost:9000/application/o/<slug>/jwks/` (с хоста); из Docker: `http://authentik-server:9000/application/o/<slug>/jwks/`

### Приложение (Application)

**Applications** → **Create** (или Directory → Applications → Create).

| Поле | Значение |
|------|----------|
| **Имя** | `farmadoc_app` |
| **Идентификатор (slug)** | `farmadoc_app` (или `farmadoc-app` — должен совпадать в BFF и Kong) |
| **Провайдер** | Выберите созданный провайдер «farmadoc_public_explicit_authentication_flow» |
| **Режим механизма политики** | any |

Redirect URI и параметры OAuth2 задаются у провайдера; у приложения указывается только привязка к провайдеру.

### Краткая сводка

| Объект | Имя / идентификатор | Redirect URI |
|--------|----------------------|--------------|
| Провайдер | farmadoc_public_explicit_authentication_flow | — |
| Приложение | farmadoc_app (имя и slug) | — |
| Провайдер → Redirect URIs | — | `http://localhost:3000/callback`; при доступе по IP — `http://<IP>:3000/callback` |

### BFF и SPA ([frontend/](../frontend/))

В `.env` задайте: `OIDC_DISCOVERY_URL`, `OIDC_REDIRECT_URI` и **обязательно** `OIDC_CLIENT_ID`. **Client ID** берётся в Authentik: **Directory** → **Providers** → выберите ваш OIDC-провайдер → в карточке провайдера скопируйте поле **Client ID**. Без верного Client ID Authentik вернёт «Client ID Error». После смены `.env`: `docker compose up -d bff`. См. [.env.example](../../.env.example).

**Ошибка `invalid_grant` (redirect_uri не совпадает):** BFF считает `redirect_uri` по заголовку **Host** запроса (при доступе по `http://192.168.173.157:3000` получится `http://192.168.173.157:3000/callback`). В настройках провайдера Authentik в **Redirect URIs** должна быть **точно такая же** строка (без завершающего слэша). Чтобы увидеть, какой `redirect_uri` уходит при обмене кода: `docker compose logs bff` — в логах строка `token_exchange` с полем `redirect_uri`. Добавьте это значение в Redirect URIs провайдера, если его там ещё нет.

### Kong: проверка JWT по JWKS

Kong (OSS) использует плагин **jwt** с публичным ключом из Authentik. Если при вызове API получаете **401 "No credentials found for given 'kid'"**, подставьте в Kong ключи из JWKS Authentik. Из корня репозитория:

```bash
cd iam/kong/scripts && python3 fetch-authentik-jwks-pem.py http://localhost:9000/application/o/ВАШ_SLUG/jwks/ --update ../kong.yml
```

Замените `ВАШ_SLUG` на slug приложения (например `farmadoc-app` или `farmadoc_app`). Затем: `docker compose restart kong`. Подробнее: [kong.md](kong.md).

---

## Интеграция с Kong (issuer и JWT)

Kong проверяет JWT по OpenID Connect: сверяет подпись и при необходимости утверждение `iss` с данными Authentik. В Kong OSS используется плагин **jwt** с ключами из JWKS Authentik (см. выше). URL документа Discovery провайдера (для справки):

```
http://authentik-server:9000/application/o/<slug>/.well-known/openid-configuration/
```

`<slug>` — slug приложения в Authentik (например `farmadoc-app` или `farmadoc_app`). Хост `authentik-server:9000` — из сети Docker.

**Где править:** `iam/kong/kong.yml`, блок плагина jwt (ключи подставляются скриптом `iam/kong/scripts/fetch-authentik-jwks-pem.py`). После изменений: `docker compose restart kong`.

**Проверка:** запрос к `http://localhost:8001/api/...` без токена — 401; с валидным Bearer-токеном от Authentik — ответ от backend.

---

## Переменные окружения (справочник)

**Обязательные для запуска (2026.2):** `PG_PASS`, `AUTHENTIK_SECRET_KEY` (см. [.env.example](../../.env.example)).

**Опционально (скрипт authentik-setup.sh при применении blueprint):** `AUTHENTIK_WAIT_ATTEMPTS` (по умолчанию 60), `AUTHENTIK_WAIT_DELAY` (с, по умолчанию 2) — ожидание готовности API. Для передачи URL и токена: аргументы скрипта или `AUTHENTIK_URL`, `AUTHENTIK_TOKEN`.

---

## API-токен

Нужен для скрипта применения blueprint и для вызовов REST API.

**Получение:** панель Authentik → **System** → **Tokens** → **Create** → укажите Identifier (например `blueprint-apply`) → **Create**. Токен показывается один раз — сохраните в `AUTHENTIK_TOKEN` или передайте в скрипт аргументом.

**Проверка токена и клиента:** скрипт [../authentik/scripts/check-authentik-token.py](../authentik/scripts/check-authentik-token.py) (если есть в репозитории) проверяет доступ к API и обмен токена/клиента. Запуск из корня репо: `cd iam/authentik/scripts && python3 check-authentik-token.py` (переменные `AUTHENTIK_URL`, `CLIENT_ID` при необходимости).

---

## Доступ и остановка

- **С хоста:** `http://localhost:9000`. С другого ПК — `http://<IP>:9000` или SSH-туннель: `ssh -L 9000:localhost:9000 user@remote-host`. Порт 9443 — для HTTPS при настройке TLS.
- **Из контейнеров** в сети `farmadoc-network`: `http://authentik-server:9000`.

**Остановка:**

```bash
docker compose stop authentik-server authentik-worker authentik-postgresql authentik-redis
```

**Полное удаление** (контейнеры и тома Authentik): из корня репозитория выполните `./iam/authentik/scripts/uninstall-authentik.sh`. Запрос подтверждения можно пропустить флагом `-f` или `--force`. Kong зависит от authentik-server — после удаления Authentik Kong нужно остановить или изменить конфиг.

**Данные:** тома `authentik_database`, `authentik_redis`, `authentik_media`, `authentik_templates`. Сброс для повторного initial-setup: см. скрипты в `iam/authentik/scripts/` (если есть reset-authentik.sh).

---

## Устранение неполадок

| Симптом | Действие |
|--------|----------|
| В браузере «failed to connect to authentik backend: authentik starting» | Сервер ещё поднимается (миграции 1–3 мин). Подождите, обновите страницу. Логи: `docker compose logs -f authentik-server`. |
| В логах «database "authentik" does not exist» | Для 2026.2 БД создаётся контейнером authentik-postgresql при первом запуске. Убедитесь, что контейнер authentik-postgresql запущен и здоров: `docker compose ps authentik-postgresql`. |
| Скрипт authentik-setup.sh: «Authentik API не ответил за отведённое время» | Увеличьте ожидание: `AUTHENTIK_WAIT_ATTEMPTS=90 AUTHENTIK_WAIT_DELAY=3 ./iam/authentik/scripts/authentik-setup.sh`. Проверьте логи: `docker compose logs -f authentik-server`. Запускайте скрипт с `SKIP_DOCKER_SETUP=1` после того, как Authentik уже поднят через `docker compose up`. |
| Скрипт: «Token invalid/expired» или HTTP 401/403 | Создайте токен в панели: **System** → **Tokens** → Create, скопируйте и передайте в скрипт: `SKIP_DOCKER_SETUP=1 ./iam/authentik/scripts/authentik-setup.sh -e http://localhost:9000 'ваш-токен'`. |
| Скрипт: HTTP 405 при применении blueprint | Примените blueprint вручную: **Customization** → **Blueprints** → **Apply blueprint** → загрузите `iam/authentik/blueprints/farmadoc-oidc.yaml`. |
| Порт 9000 занят при SSH-туннеле | Используйте другой локальный порт: `ssh -L 9001:localhost:9000 user@remote-host`, затем `http://localhost:9001` (и при вызове скрипта: `AUTHENTIK_URL=http://localhost:9001`). |

---

## См. также

- [kong.md](kong.md) — API Gateway, плагин JWT и JWKS Authentik
- [frontend.md](frontend.md) — BFF и SPA (OIDC + PKCE), запуск и развёртывание
- [auth-flow.md](auth-flow.md) — схема OAuth2/OIDC: приложение → Authentik → Kong → backend
