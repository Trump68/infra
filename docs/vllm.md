# vLLM в Docker

Сервис для запуска моделей с Hugging Face: эмбеддинги и (при необходимости) LLM. API совместим с OpenAI (chat, completions, embeddings).

## Настройка модели

1. Скопируйте пример env и задайте модель:
   ```bash
   cp .env.example .env
   # Отредактируйте .env: VLLM_MODEL=org/name-model
   ```

2. Примеры моделей для эмбеддингов (Hugging Face):
   - `BAAI/bge-small-en-v1.5`
   - `sentence-transformers/all-MiniLM-L6-v2`
   - `intfloat/e5-small-v2`

3. Для gated-моделей в `.env` добавьте: `HF_TOKEN=hf_...`

## Запуск

```bash
docker-compose up -d vllm
```

Первый запуск скачает модель в volume `vllm_cache` (каталог Hugging Face cache).

## Доступ

- С хоста: `http://localhost:8000`
- Из контейнеров в сети `milvus-network` (в т.ч. n8n): `http://vllm:8000`

Эндпоинты (OpenAI-совместимые):
- Эмбеддинги: `POST /v1/embeddings`
- Chat: `POST /v1/chat/completions`

## GPU

По умолчанию контейнер без GPU (CPU). Для GPU раскомментируйте секцию `deploy.resources.reservations` у сервиса `vllm` в `docker-compose.yml` и убедитесь, что установлен NVIDIA Container Toolkit.

## Смена модели

Поменяйте `VLLM_MODEL` в `.env` и перезапустите:

```bash
docker-compose up -d --force-recreate vllm
```
