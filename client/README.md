# Продакшен-SPA (OIDC: Kong + Authentik)

Браузерный клиент, работающий по OIDC (Authorization Code + PKCE) с Kong и Authentik так же, как в проде. Конфигурация через переменные окружения; BFF отдаёт конфиг, обменивает code на токен и проксирует запросы к API в Kong.

## Требования

- Authentik с провайдером OIDC и приложением (например из blueprint `farmadoc-oidc`). В провайдере должен быть указан **Redirect URI** вашего приложения (например `http://localhost:3000/callback` для локального запуска).
- Kong с настроенной проверкой JWT по issuer Authentik.
- Python 3 для запуска BFF.

## Запуск (локально)

Из корня репозитория:

```bash
cd client
python3 serve.py
```

Откройте в браузере: **http://localhost:3000/**

По умолчанию BFF подставляет конфиг для localhost: discovery собирается из `AUTHENTIK_BASE_URL` + `OIDC_APP_SLUG`, redirect URI — `http://localhost:3000/callback`, запросы к API идут на тот же origin (BFF проксирует `/api` в Kong).

## Переменные окружения

| Переменная | По умолчанию | Описание |
|------------|--------------|----------|
| `OIDC_DISCOVERY_URL` | — | Полный URL discovery (например `http://localhost:9000/application/o/farmadoc_client/.well-known/openid-configuration/`). Если не задан, собирается из `AUTHENTIK_BASE_URL` и `OIDC_APP_SLUG`. |
| `OIDC_ISSUER` | — | Альтернатива `OIDC_DISCOVERY_URL` (то же значение). |
| `OIDC_CLIENT_ID` | (из `CLIENT_ID`) | Client ID публичного OAuth2-клиента. |
| `OIDC_REDIRECT_URI` | `http://localhost:3000/callback` | Redirect URI; должен совпадать с одним из URI в настройках провайдера Authentik. |
| `KONG_API_BASE_URL` | пусто | Базовый URL API (Kong). Пусто — SPA ходит на тот же origin по `/api`, BFF проксирует в Kong. |
| `KONG_INTERNAL_URL` | `http://localhost:8001` | URL Kong, на который BFF проксирует запросы `/api`. |
| `AUTHENTIK_BASE_URL` | `http://localhost:9000` | Используется для сборки discovery URL, если `OIDC_DISCOVERY_URL` не задан. |
| `OIDC_APP_SLUG` | `farmadoc_client` | Slug приложения в Authentik для сборки discovery URL. |
| `PORT` | `3000` | Порт BFF. |

Для прода задайте `OIDC_DISCOVERY_URL`, `OIDC_CLIENT_ID`, `OIDC_REDIRECT_URI` (например `https://app.example.com/callback`). В Authentik в провайдере добавьте этот redirect URI (в blueprint или в UI).

## Развёртывание в проде

1. **Конфиг:** задайте переменные окружения (или секрет-менеджер) на сервере, где крутится BFF. Не коммитьте секреты в репозиторий.
2. **Статика и BFF:** раздавайте файлы из `client/` (например nginx для статики) и запускайте `serve.py` за reverse proxy, либо один сервер (как сейчас) раздаёт и статику, и `/config.json`, `/auth/exchange`, `/api`.
3. **Redirect URI:** в Authentik у провайдера должен быть redirect URI вашего приложения (например `https://your-domain.com/callback`). Можно добавить в `authentik/blueprints/farmadoc-oidc.yaml` и применить blueprint заново или добавить в UI.
4. **Kong:** issuer в Kong должен указывать на discovery вашего провайдера Authentik; запросы к API с вашего домена проксируйте на Kong или задайте `KONG_API_BASE_URL` и настройте CORS на Kong для origin SPA.

## Отличия от тестового SPA (authentik/spa-test)

- OIDC по discovery и PKCE (Authorization Code + code_verifier/code_challenge).
- Конфиг через `/config.json` и переменные окружения, без захардкоженных URL в коде.
- Один билд пригоден для разных окружений (dev/prod) за счёт конфига и redirect_uri в Authentik.

Подробнее о потоке авторизации: [docs/auth-flow.md](../docs/auth-flow.md). Настройка Authentik и Kong: [authentik/doc/authentik.md](../authentik/doc/authentik.md), [kong/doc/kong.md](../kong/doc/kong.md). Сравнение статического SPA и SPA + BFF (безопасность): [spa-vs-bff.md](spa-vs-bff.md).
