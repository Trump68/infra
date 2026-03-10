# Milvus и n8n

## Запуск Milvus

```bash
docker compose up -d
```

Проверка здоровья:
```bash
docker compose ps
# Все сервисы (etcd, minio, milvus) должны быть Up (healthy)
```

## Подключение из n8n

### Вариант 1: n8n в Docker (рекомендуется)

Подключите контейнер n8n к той же сети, что и Milvus:

```yaml
# В docker-compose, где запущен n8n, добавьте:
networks:
  default:
    name: milvus-network
    external: true
```

Либо при запуске n8n:
```bash
docker run -d --network milvus-network ... n8nio/n8n
```

**Параметры подключения к Milvus из n8n:**
- **Host:** `milvus` (имя сервиса)
- **Port:** `19530`

### Вариант 2: n8n на хосте

Если n8n запущен не в Docker (или в другой сети), используйте хост машины:

- **Host:** `localhost` (или IP хоста)
- **Port:** `19530`

## Версия

- Milvus: **v2.6.11** (последняя стабильная на момент настройки)
- Порт gRPC: **19530**

## Остановка

```bash
docker compose down
# С данными:
# docker compose down  (volumes сохраняются)
# Полная очистка: docker compose down -v
```
