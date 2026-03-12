# Kong (API Gateway)

Единая точка входа для API. Проверяет JWT через OpenID Connect (Authentik) и проксирует запросы на backend.

**Первый этап:** только HTTP по localhost и портам; TLS и домены (reverse proxy с HTTPS) — при необходимости позже.

**Примечание:** плагин `openid-connect` входит в Kong Enterprise. В Kong OSS (образ `kong:3.7`) этот плагин может быть недоступен; тогда используйте Kong Enterprise или настройте плагин `jwt` с публичным ключом (JWKS) из Authentik вручную.

## Запуск

1. По умолчанию Kong проксирует на **placeholder-сервис backend** (nginx в compose) — цепочку можно проверить без внешнего API. Для реального backend замените в `kong/kong.yml` url на свой (например `http://host.docker.internal:8080` для сервиса на хосте).
2. Убедитесь, что **issuer** в плагине openid-connect совпадает с URL discovery провайдера Authentik (см. [authentik/doc/authentik.md](../authentik/doc/authentik.md)).

3. Поднимите сервисы (включая placeholder backend):
   ```bash
   docker compose up -d backend kong
   ```

## Порты

- **8001** — HTTP proxy (внешний порт; 8000 занят vLLM). На первом этапе используйте его для доступа к API.
- 8444 — HTTPS proxy (для этапа с TLS).

Запросы к API: `http://localhost:8001/api/...` с заголовком `Authorization: Bearer <access_token>` (токен из Authentik).

## Настройка backend и issuer

Файл `kong/kong.yml`:

- **Backend URL:** по умолчанию `http://backend:80` — placeholder-сервис (nginx) в compose для проверки цепочки. Для реального API замените на адрес своего backend (доступный с хоста Kong), например `http://host.docker.internal:8080`. После изменения перезапустите Kong: `docker compose up -d kong`.
- **Issuer:** в плагине `openid-connect` параметр `config.issuer` должен совпадать с discovery URL провайдера в Authentik (например `http://authentik-server:9000/application/o/default/.well-known/openid-configuration/`). Slug провайдера должен совпадать с тем, что создан в Authentik.

## Проверка

1. Без токена запрос к `http://localhost:8001/api/...` должен вернуть 401.
2. С валидным Bearer-токеном от Authentik запрос должен проксироваться на backend и вернуть его ответ.

## Остановка

```bash
docker compose stop kong
```

Конфигурация хранится в репозитории (`kong/kong.yml`), состояние Kong не персистентное (DB-less).
