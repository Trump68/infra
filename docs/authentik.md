# Authentik (OAuth2/OIDC)

Сервер авторизации (IdP) для единого входа. Выдаёт токены для браузерного приложения; Kong проверяет их через OpenID Connect. Использует **отдельную БД `authentik`** на том же экземпляре PostgreSQL, что и остальные сервисы.

**Первый этап:** только HTTP по localhost; TLS и домены — при необходимости позже.

## Запуск

1. Задайте в `.env`:
   - `AUTHENTIK_SECRET_KEY` — случайная строка (например `openssl rand -base64 48`)
   - Учётные данные PostgreSQL (`POSTGRES_USER`, `POSTGRES_PASSWORD`) — Authentik подключается к той же инстанции, БД `authentik` создаётся автоматически при первой инициализации postgres (скрипт `postgres/init-authentik-db.sh`). Если postgres уже был запущен ранее без этого скрипта, создайте БД вручную: `docker exec postgres psql -U postgres -c "CREATE DATABASE authentik;"`

2. Поднимите сервисы:
   ```bash
   docker compose up -d postgres redis authentik-server authentik-worker
   ```

3. При первом запуске откройте в браузере:
   ```
   http://localhost:9000/if/flow/initial-setup/
   ```
   Задайте пароль суперадмина. Учётная запись суперадмина: **логин `akadmin`**, пароль задаётся на этом шаге. В данной конфигурации для входа в панель используйте: **akadmin** / **admin** (если задали этот пароль при initial-setup).

   **Доступ с другого ПК (удалённая машина):** откройте `http://<IP-хоста>:9000/if/flow/initial-setup/` либо SSH-туннель: `ssh -L 9000:localhost:9000 user@remote-host`, затем `http://localhost:9000/...`. Если локальный порт 9000 уже занят, используйте другой: `ssh -L 9001:localhost:9000 user@remote-host` и откройте `http://localhost:9001/if/flow/initial-setup/`.

   **Если в браузере «failed to connect to authentik backend: authentik starting»:** сервер ещё поднимается (при первом запуске — миграции БД, может занять 1–3 минуты). Подождите и обновите страницу. Прогресс: `docker compose logs -f authentik-server`.

   **Если в логах «database \"authentik\" does not exist»:** БД не была создана (postgres поднят до добавления init-скрипта). Создайте вручную: `docker exec postgres psql -U postgres -c "CREATE DATABASE authentik;"`, затем `docker compose restart authentik-server authentik-worker`.

## Настройка OIDC для Kong и браузерного приложения

Подробное пошаговое заполнение всех форм мастера создания провайдера: [authentik_setup.md](authentik_setup.md). Готовый blueprint для программного создания провайдера и приложения Farmadoc: [authentik/blueprints/farmadoc-oidc.yaml](../authentik/blueprints/farmadoc-oidc.yaml) (применение через UI или API — см. раздел «Автоматизация» в authentik_setup.md).

1. В веб-интерфейсе Authentik: **Directory** → **Providers** → **Create** → **OpenID Connect Provider**.
2. Задайте имя и **Authorization flow** (создайте при необходимости flow с типом Authorization Code).
3. Сохраните и запомните **slug** провайдера (например `default`).
4. **Applications** → **Create** → привяжите созданный Provider, укажите **Redirect URIs** вашего SPA (например `http://localhost:3000/callback`).
5. **URL для Kong (issuer / discovery):**
   - Внутри сети Docker (как в нашем `kong/kong.yml`):  
     `http://authentik-server:9000/application/o/<slug>/.well-known/openid-configuration/`
   - Подставьте ваш `<slug>` провайдера. Если slug = `default`, путь уже совпадает с примером в `kong/kong.yml`.

Используйте этот же issuer в конфиге Kong (см. [kong.md](kong.md)), чтобы Kong проверял JWT по Authentik.

**Где взять API-токен (для скрипта и API):** войдите в панель Authentik (akadmin / ваш пароль) → **System** → **Tokens** → **Create** → укажите **Identifier** (например `blueprint-apply`), при необходимости выберите права (для применения blueprint нужны права на blueprints; можно дать полные права администратора) → **Create**. Токен показывается **один раз** — скопируйте его и сохраните (например в `AUTHENTIK_TOKEN` или передайте в скрипт).

**Автоматическое получение токена (bootstrap):** при первом запуске Authentik можно задать переменные окружения `AUTHENTIK_BOOTSTRAP_TOKEN` и `AUTHENTIK_BOOTSTRAP_PASSWORD` (и при необходимости `AUTHENTIK_BOOTSTRAP_EMAIL`) — тогда при инициализации будет создан аккаунт akadmin с этим паролем и выдан API-токен, равный значению `AUTHENTIK_BOOTSTRAP_TOKEN`. Его можно передать в скрипт применения blueprint без ручного создания токена в UI. Подробнее и ограничения по версиям — в [authentik_setup.md](authentik_setup.md#автоматизация-токена-bootstrap).

## Доступ

- С хоста (первый этап): `http://localhost:9000`. С другого компьютера — `http://<IP-этого-хоста>:9000` или SSH-туннель; если локальный 9000 занят — туннель на другой порт, например `-L 9001:localhost:9000`, затем `http://localhost:9001`. Порт 9443 (HTTPS) — при настройке TLS позже.
- Из контейнеров в сети `farmadoc-network`: `http://authentik-server:9000`.

## Остановка

```bash
docker compose stop authentik-server authentik-worker
```

Данные Authentik хранятся в БД `authentik` на том же PostgreSQL (volume `postgres_data`) и в volume `authentik_media`.
