# Документация IAM (Identity and Access Management)

Документация по компонентам каталога `iam/`: Authentik, Kong, frontend (BFF + SPA), backend.

| Документ | Содержание |
|----------|------------|
| [auth-flow.md](auth-flow.md) | Поток авторизации: браузер → Authentik → Kong → backend |
| [authentik.md](authentik.md) | Authentik (OIDC/OAuth2): установка, провайдер, приложение, переменные |
| [kong.md](kong.md) | Kong (API Gateway): JWT, прокси на backend, скрипты настройки |
| [frontend.md](frontend.md) | Продакшен-SPA (BFF + OIDC + PKCE): запуск, переменные, развёртывание |
| [spa-vs-bff.md](spa-vs-bff.md) | Статический SPA и SPA + BFF: сравнение и безопасность |

Конфигурация и скрипты: `iam/authentik/`, `iam/kong/`, `iam/frontend/`, `iam/backend/`. Запуск сервисов — из корня репозитория: `docker compose up -d …` (см. корневой [README](../../README.md) и [docker-compose.yml](../../docker-compose.yml)).
