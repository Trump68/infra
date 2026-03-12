# Kong (API Gateway)

Единая точка входа для API. Проверяет JWT через OpenID Connect (Authentik) и проксирует запросы на backend.

**Первый этап:** только HTTP по localhost и портам; TLS и домены (reverse proxy с HTTPS) — при необходимости позже.

**Примечание:** плагин `openid-connect` входит в Kong Enterprise. В Kong OSS (образ `kong:3.7`) этот плагин может быть недоступен; тогда используйте Kong Enterprise или настройте плагин `jwt` с публичным ключом (JWKS) из Authentik вручную.

## Запуск

1. По умолчанию Kong проксирует на **placeholder-сервис backend** (nginx в compose). Для реального backend замените в `kong/kong.yml` url на свой (например `http://host.docker.internal:8080`).
2. Поднимите сервисы (включая placeholder backend):
   ```bash
   docker compose up -d backend kong
   ```

## Порты

- **8001** — HTTP proxy (внешний порт; 8000 занят vLLM). На первом этапе используйте его для доступа к API.
- 8444 — HTTPS proxy (для этапа с TLS).

Запросы к API: `http://localhost:8001/api/...`. В текущей конфигурации плагин проверки JWT отключён (openid-connect есть только в Kong Enterprise), поэтому запросы проксируются на backend без проверки токена. Для проверки Bearer-токенов Authentik настройте плагин **jwt** и укажите публичный ключ (PEM из JWKS Authentik) — см. раздел «Kong OSS: проверка JWT через плагин jwt» ниже.

## Доступ (как открыть в браузере / с другого ПК)

- **С хоста:** `http://localhost:8001` (проверка: `http://localhost:8001/api/...` — без плагина JWT вернётся ответ backend; с плагином jwt — без токена 401, с валидным Bearer — ответ backend).
- **С другого ПК:** `http://<IP-хоста>:8001` или **SSH-туннель:** `ssh -L 8001:localhost:8001 user@remote-host`. Если порт 8001 занят локально — другой локальный порт, например `-L 8002:localhost:8001`, тогда обращайтесь по `http://localhost:8002`.
- **Из контейнеров** в сети `farmadoc-network`: `http://kong:8000` (внутренний порт Kong).
- Порт **8444** — для HTTPS proxy при настройке TLS.

## Настройка backend

Файл `kong/kong.yml`:

- **Backend URL:** по умолчанию `http://backend:80` — placeholder-сервис (nginx) в compose. Для реального API замените на адрес своего backend (доступный из сети Kong), например `http://host.docker.internal:8080`. После изменения перезапустите Kong: `docker compose up -d kong`.
- **Проверка JWT:** в Kong OSS плагин openid-connect недоступен; используется плагин jwt с публичным ключом Authentik (см. раздел «Kong OSS: проверка JWT через плагин jwt»).

## Как проверить, что Kong работает

1. **Контейнер запущен:**
   ```bash
   docker compose ps kong
   ```
   Статус должен быть `running`. Логи: `docker compose logs kong`.

2. **Прокси отвечает:**
   ```bash
   curl -i http://localhost:8001/api/
   ```
   Без плагина JWT — ответ backend (например HTML от nginx). С включённым плагином jwt — без токена ожидается `401 Unauthorized`.

3. **С валидным Bearer-токеном — ответ backend:**
   Получите access token через Authentik (OAuth2/OIDC flow для приложения, привязанного к провайдеру из [manual-provider-app-settings.md](../../authentik/doc/manual-provider-app-settings.md)), затем:
   ```bash
   curl -i -H "Authorization: Bearer <ваш_access_token>" http://localhost:8001/api/
   ```
   Ожидается ответ от backend (например HTML от placeholder nginx). Если снова 401 — проверьте issuer в `kong/kong.yml` и что токен выдан тем же провайдером Authentik.

4. **Маршрут не из конфига:** запрос к пути, не входящему в `paths` (например `http://localhost:8001/` или `http://localhost:8001/other`), может вернуть 404 — это нормально, значит Kong обрабатывает только `/api`.

## Если порт 8001: Connection refused

Проверьте, что контейнер действительно работает и слушает порт:

```bash
docker compose ps kong
docker compose logs kong --tail 50
```

- Если контейнер в состоянии **Exited** или постоянно **Restarting** — смотрите логи. Частая причина: в Kong **OSS** плагин **openid-connect** недоступен (только Kong Enterprise). В текущем `kong.yml` плагин openid-connect убран — Kong стартует и проксирует без проверки JWT. Для проверки токенов Authentik настройте плагин **jwt** (см. раздел ниже).
- Если контейнер **Running**, но порт 8001 не отвечает — проверьте, что порт не занят другим процессом: `ss -tlnp | grep 8001` или `docker compose port kong 8000`.
- **Connection refused** на `curl http://127.0.0.1:8001/api/` — контейнер мог упасть после старта (ошибка конфига/плагина). Запустите `sudo ./kong/scripts/setup-kong-jwt-auth.sh` — при 000 скрипт выведет `docker compose ps kong` и логи Kong; либо вручную: `sudo docker compose ps kong` и `sudo docker compose logs kong --tail 50`.

## Kong OSS: проверка JWT через плагин jwt

В Kong OSS нет плагина openid-connect. В `kong/kong.yml` уже включены плагин **jwt** и consumer **authentik**; нужно подставить реальный публичный ключ (PEM) и `kid` из провайдера Authentik.

### Автоматическая настройка (рекомендуется)

Убедитесь, что **Authentik запущен** и провайдер создан (см. [manual-provider-app-settings.md](../../authentik/doc/manual-provider-app-settings.md)). Из **корня репозитория** выполните:

```bash
./kong/scripts/setup-kong-jwt-auth.sh
```

Скрипт установит при необходимости `cryptography`, запросит JWKS у Authentik (по умолчанию приложение `farmadoc_app`: `http://localhost:9000/application/o/farmadoc_app/jwks/`), обновит секцию `consumers` в `kong/kong.yml` и перезапустит Kong. Для другого приложения/провайдера передайте URL JWKS:

```bash
./kong/scripts/setup-kong-jwt-auth.sh "http://localhost:9000/application/o/<slug>/jwks/"
```

Без перезапуска Kong (только обновить конфиг): `./kong/scripts/setup-kong-jwt-auth.sh --no-restart`. Для теста или офлайн можно передать путь к локальному файлу JWKS (JSON): `./kong/scripts/setup-kong-jwt-auth.sh kong/scripts/test-data/jwks-sample.json --no-restart`.

### Пошаговая настройка (вручную)

1. **Запустите Authentik** (и создайте провайдер по [manual-provider-app-settings.md](../../authentik/doc/manual-provider-app-settings.md), если ещё не создан).

2. **Установите зависимость** (один раз): `pip install cryptography`

3. **Получите kid и PEM** из JWKS провайдера:
   ```bash
   cd kong/scripts
   python3 fetch-authentik-jwks-pem.py
   ```
   Для другого приложения: `python3 fetch-authentik-jwks-pem.py "http://localhost:9000/application/o/<slug>/jwks/"`

4. **Подставьте вывод в `kong/kong.yml`:** замените `REPLACE_WITH_KID` на выведенный `kid` и блок `rsa_public_key` — на выведенный PEM. Либо готовую секцию `consumers`: `python3 fetch-authentik-jwks-pem.py --yaml` и вставьте в `kong/kong.yml`. Либо автоматическая подстановка в файл: `python3 fetch-authentik-jwks-pem.py --update ../../kong/kong.yml` (из `kong/scripts`).

5. **Перезапустите Kong:** `docker compose restart kong`

6. **Проверка:** без токена `curl -i http://localhost:8001/api/` — 401; с валидным Bearer — ответ backend.

Если Kong не стартует с ошибкой про разбор ключа — в конфиге всё ещё стоит placeholder. Запустите автоматический скрипт или выполните шаги 3–5 вручную.

Документация Kong: [JWT Plugin](https://docs.konghq.com/hub/kong-inc/jwt/).

## Остановка

```bash
docker compose stop kong
```

Конфигурация хранится в репозитории (`kong/kong.yml`), состояние Kong не персистентное (DB-less).
