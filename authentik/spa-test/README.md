# Тестовый SPA-клиент (Authentik + Kong)

Минимальное веб-приложение для проверки цепочки: вход через Authentik (OAuth2) и вызов API через Kong с Bearer-токеном.

## Требования

- В Authentik у провайдера должен быть указан **Redirect URI**: `http://localhost:3000/callback` (или `http://localhost:PORT/callback`, если запускаете с другим портом).
- Запущены Authentik и Kong (и backend), см. основной README репозитория.

## Запуск

Из каталога репозитория:

```bash
cd authentik/spa-test
python3 serve.py
```

Или с портом и переменными:

```bash
AUTHENTIK_URL=http://localhost:9000 CLIENT_ID=xxx KONG_URL=http://localhost:8001 python3 serve.py
PORT=3001 python3 serve.py   # тогда Redirect URI = http://localhost:3001/callback
```

Откройте в браузере: **http://localhost:3000/**

## Как пользоваться

1. Нажмите **«Войти через Authentik»** — откроется страница входа Authentik.
2. Войдите (логин/пароль пользователя Authentik).
3. После входа произойдёт редирект на `http://localhost:3000/callback?code=...`; приложение обменяет `code` на токен.
4. Нажмите **«Вызвать API через Kong»** — запрос уйдёт в Kong с заголовком `Authorization: Bearer <token>`. В блоке «Ответ API» появится ответ от backend (через Kong).

## Переменные окружения

| Переменная      | По умолчанию              | Описание                    |
|-----------------|----------------------------|-----------------------------|
| `AUTHENTIK_URL` | `http://localhost:9000`     | Базовый URL Authentik       |
| `CLIENT_ID`     | (значение из скрипта)      | Client ID OAuth2-провайдера |
| `KONG_URL`      | `http://localhost:8001`    | URL Kong (proxy)            |
| `PORT`          | `3000`                     | Порт сервера SPA            |

Redirect URI в настройках провайдера Authentik должен совпадать с `http://localhost:PORT/callback`.
