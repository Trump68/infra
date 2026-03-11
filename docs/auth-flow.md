# Поток авторизации: браузерное приложение — OAuth2 — Kong — Authentik — backend

Схема работы связки для внешнего браузерного приложения (SPA), которое вызывает API через Kong с авторизацией через Authentik.

## Участники

- **Браузерное приложение (SPA)** — реализуется отдельно; логин и получение токенов через Authentik, вызовы API — через Kong с Bearer-токеном.
- **Authentik** — IdP (OAuth2/OIDC): страница входа, выдача access_token и при необходимости id_token.
- **Kong** — API Gateway: проверяет JWT по Authentik (OIDC), проксирует запросы на backend.
- **Backend** — ваш сервис; в инфраструктуре задаётся только как upstream в Kong.

## Последовательность

1. Пользователь открывает SPA; для доступа к API нужна авторизация.
2. SPA перенаправляет на Authentik (Authorization Code или другой поддерживаемый flow), пользователь входит.
3. Authentik редиректит обратно в SPA с кодом или токенами; SPA получает `access_token`.
4. Запросы к API идут на Kong по HTTP (на первом этапе: `http://localhost:8001/api/...`) с заголовком `Authorization: Bearer <access_token>`.
5. Kong проверяет токен через OpenID Connect (Authentik): issuer, подпись, при необходимости — introspection.
6. При успешной проверке Kong проксирует запрос на backend; ответ возвращается в SPA.

## Что настроить в Authentik

- **Provider** типа OpenID Connect и **Application** с redirect URIs вашего SPA.
- Issuer / discovery URL этого провайдера указать в Kong (`kong/kong.yml`, плагин openid-connect), чтобы Kong доверял только токенам от этого IdP.

Подробнее: [authentik.md](authentik.md), [kong.md](kong.md).
