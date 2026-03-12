# farmadoc-infrastructure

Инфраструктура Farmadoc (Docker): Milvus, vLLM (эмбеддинги), PostgreSQL, Kong (API Gateway), Authentik (OAuth2/OIDC), Redis.

**Первый этап:** доступ только по HTTP на localhost и указанных портах; домены и TLS (reverse proxy с HTTPS) при необходимости добавляются позже.

## Быстрый старт

```bash
cp .env.example .env
# Отредактируйте .env: задайте AUTHENTIK_SECRET_KEY и при необходимости POSTGRES_USER/POSTGRES_PASSWORD (postgres и Authentik используют один инстанс)
docker compose up -d
```

**Откуда взять значения:** `AUTHENTIK_SECRET_KEY` — сгенерируйте случайную строку, например: `openssl rand -base64 48`. `POSTGRES_USER` и `POSTGRES_PASSWORD` — придумайте сами (логин/пароль БД PostgreSQL); для локальной разработки можно оставить по умолчанию `postgres` / `postgres`, если в `.env.example` они закомментированы — раскомментируйте и подставьте или добавьте в `.env`.

Полный стек: etcd, minio, milvus, vllm_emb, postgres, redis, authentik-server, authentik-worker, backend (placeholder), kong. Только Milvus: `docker compose up -d etcd minio milvus`. Только авторизация: `docker compose up -d postgres redis authentik-server authentik-worker backend kong`.

## Milvus

Векторная БД Milvus (v2.6.11) поднимается через Docker Compose вместе с etcd и MinIO.

**Доступ для n8n:**
- Из контейнера в сети `farmadoc-network`: хост `milvus`, порт `19530`
- С хоста: `localhost:19530`

Подробнее: [docs/milvus-n8n.md](docs/milvus-n8n.md)

## vLLM (эмбеддинги)

Сервис `vllm_emb` для запуска моделей с Hugging Face (эмбеддинги). API совместим с OpenAI.

- Модель и GPU задаются в `docker-compose.yml` (модель в `command`, GPU в `deploy.resources.reservations`).
- Доступ: с хоста `http://localhost:8000`, из n8n в сети `farmadoc-network` — `http://vllm_emb:8000`

Подробнее: [docs/vllm.md](docs/vllm.md), [docs/nvidia-driver-ubuntu.md](docs/nvidia-driver-ubuntu.md)

## PostgreSQL

Сервис `postgres` (PostgreSQL 17). Учётные данные — переменные окружения (по умолчанию из [.env.example](.env.example): user/password/db = `postgres`).

- С хоста: `localhost:5432`
- Из контейнеров в сети `farmadoc-network`: хост `postgres`, порт `5432`

## Kong и Authentik (OAuth2/OIDC)

**Kong** — API Gateway: единая точка входа для API, проверка JWT через OpenID Connect, проксирование на backend. На первом этапе используйте HTTP: порт **8001**. По умолчанию upstream — placeholder-сервис **backend** (nginx в compose); для реального API замените url в `kong/kong.yml`. Issuer OIDC — URL discovery провайдера Authentik.

**Authentik** — сервер авторизации (IdP): логин, выдача токенов для браузера. На первом этапе используйте HTTP: порт **9000**. Использует Redis и отдельную БД `authentik` на том же PostgreSQL. Первый вход: `http://localhost:9000/if/flow/initial-setup/`.

Подробнее: [docs/kong.md](docs/kong.md), [authentik/doc/authentik.md](authentik/doc/authentik.md), [docs/auth-flow.md](docs/auth-flow.md).

## Дополнительная документация

- [docs/milvus-n8n.md](docs/milvus-n8n.md) — Milvus и n8n
- [docs/vllm.md](docs/vllm.md) — vLLM, модели, GPU
- [docs/kong.md](docs/kong.md) — Kong, OIDC, backend
- [authentik/doc/authentik.md](authentik/doc/authentik.md) — Authentik: установка (bootstrap + скрипт), OIDC, ручная настройка провайдера
- [docs/auth-flow.md](docs/auth-flow.md) — поток: браузер ↔ Authentik ↔ Kong ↔ backend
- [docs/docker-without-sudo.md](docs/docker-without-sudo.md) — запуск Docker без sudo
- [docs/nvidia-driver-ubuntu.md](docs/nvidia-driver-ubuntu.md) — установка драйвера NVIDIA на Ubuntu
