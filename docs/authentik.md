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
   Задайте пароль суперадмина (akadmin).

## Настройка OIDC для Kong и браузерного приложения

1. В веб-интерфейсе Authentik: **Directory** → **Providers** → **Create** → **OpenID Connect Provider**.
2. Задайте имя и **Authorization flow** (создайте при необходимости flow с типом Authorization Code).
3. Сохраните и запомните **slug** провайдера (например `default`).
4. **Applications** → **Create** → привяжите созданный Provider, укажите **Redirect URIs** вашего SPA (например `http://localhost:3000/callback`).
5. **URL для Kong (issuer / discovery):**
   - Внутри сети Docker (как в нашем `kong/kong.yml`):  
     `http://authentik-server:9000/application/o/<slug>/.well-known/openid-configuration/`
   - Подставьте ваш `<slug>` провайдера. Если slug = `default`, путь уже совпадает с примером в `kong/kong.yml`.

Используйте этот же issuer в конфиге Kong (см. [kong.md](kong.md)), чтобы Kong проверял JWT по Authentik.

## Доступ

- С хоста (первый этап): `http://localhost:9000`. Порт 9443 (HTTPS) — при настройке TLS позже.
- Из контейнеров в сети `farmadoc-network`: `http://authentik-server:9000`.

## Остановка

```bash
docker compose stop authentik-server authentik-worker
```

Данные Authentik хранятся в БД `authentik` на том же PostgreSQL (volume `postgres_data`) и в volume `authentik_media`.
