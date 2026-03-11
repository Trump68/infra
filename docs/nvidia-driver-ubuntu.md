# Установка драйвера NVIDIA на Ubuntu

## 1. Драйвер для системы (хост)

### Вариант А: через ubuntu-drivers (рекомендуется)

```bash
# Показать доступные драйверы
sudo ubuntu-drivers list

# Установить рекомендуемый драйвер
sudo ubuntu-drivers install

# Или указать версию явно, например:
# sudo ubuntu-drivers install nvidia:535
```

### Вариант Б: через графику (если есть рабочий стол)

**Параметры системы** → **Дополнительные драйверы** → выбрать драйвер NVIDIA → **Применить изменения**.

### После установки

Перезагрузите систему:

```bash
sudo reboot
```

Проверка:

```bash
nvidia-smi
```

Должна вывести информацию о GPU и версии драйвера.

---

## 2. NVIDIA Container Toolkit (для Docker)

Чтобы контейнеры (в т.ч. vLLM) могли использовать GPU, нужен NVIDIA Container Toolkit.

```bash
# Репозиторий и ключ
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list

# Установка
sudo apt update
sudo apt install -y nvidia-container-toolkit

# Привязать Docker к nvidia runtime
sudo nvidia-ctk runtime configure --runtime=docker

# Перезапустить Docker
sudo systemctl restart docker
```

Проверка из контейнера:

```bash
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi
```

---

## 3. Включить GPU для vLLM в этом проекте

В `docker-compose.yml` у сервиса `vllm_emb`:

1. Раскомментировать блок `deploy` с `nvidia`.
2. Раскомментировать строку `command` с `--gpu-memory-utilization 0.6` и закомментировать текущую `command` без этого флага.

После этого:

```bash
docker compose up -d
```

Контейнер vLLM будет использовать GPU.
