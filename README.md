# Развёртывание веб-приложения в Kubernetes с Gateway API, мониторингом и логированием

Автор: Бушков В.С.

## Краткое описание

Решение разворачивает простое веб-приложение (Nginx) в Kubernetes-кластере с полной инфраструктурой:

- **Kubernetes** (kubeadm, v1.30.14) — оркестрация
- **Flannel CNI** (v0.28.9) — сеть pod'ов
- **Nginx** — демонстрационное приложение (`Hello World!`)
- **Envoy Gateway** (v1.1.0) — реализация Gateway API
- **Prometheus** (v2.55.0) — сбор метрик
- **Fluent Bit** (v3.1.0) — сбор логов приложения

Всё развёртывание автоматизировано и сводится к трём командам.

## Архитектура

```

 [ 1. СЛОЙ ПОЛЬЗОВАТЕЛЕЙ ]
        |
        | HTTP-запрос (Внешний трафик)
        v NodePort: :31996
 ______________________________________________________________________________________
|                                                                                      |
|                                                                                      |
| [ 2. СЛОЙ МАРШРУТИЗАЦИИ ]           Namespace: [ envoy-gateway-system ]              |
|                                                                                      |
|     +--------------------------------------------------------------------------+     |
|     |                     ENVOY GATEWAY (Data Plane)                           |     |
|     |               [ Реализация Kubernetes Gateway API ]                      |     |
|     +--------------------------------------------------------------------------+     |
|___________________________________________|__________________________________________|
                                            |
                                            | Маршрутизация по правилам HTTPRoute
                                            v
 ______________________________________________________________________________________
|                                                                                      |
|                                                                                      |
| [ 3. СЛОЙ ВЕБ-ПРИЛОЖЕНИЯ ]          Namespace: [ default ]                           |
|                                                                                      |
|     +--------------------------------------------------------------------------+     |
|     |                           Service: nginx                                 |     |
|     |                       (Тип сервиса: ClusterIP)                           |     |
|     +-------------------------------------+------------------------------------+     |
|                                           |                                          |
|                                           v                                          |
|     +--------------------------------------------------------------------------+     |
|     |                             Pod: Nginx                                   |     |
|     |                  (Контейнер: nginx:stable-alpine)                        |     |
|     |    - Отдаёт контент: "Hello World!"                                      |     |
|     |    - Пишет логи запросов в: stdout / stderr                              |     |
|     +--------------------------------------------------------------------------+     |
|_______________________^_______________________________________|______________________|
                        :                                       :
   Запрос метрик (PULL) :                                       : Чтение логов (stdout)
   через PodMonitor     :                                       : из /var/log/containers
                        :                                       v
 _______________________:_______________________________________:______________________
|                       :                                       :                      |
|                       :                                       :                      |
| [ 4. СЛОЙ НАБЛЮДАЕМОСТИ ]           Namespace: [ monitoring ]                        |
|                                                                                      |
|     +-----------------------------------+   +----------------------------------+     |
|     |           PROMETHEUS              |   |           FLUENT BIT             |     |
|     |         [ Мониторинг ]            |   |          [ Сбор логов ]          |     |
|     |    Собирает метрики с Envoy       |   |      Развернут как DaemonSet     |     |
|     |    и инфраструктуры кластера      |   |      Отправляет логи в stdout/хранилище|
|     +-----------------------------------+   +----------------------------------+     |
|______________________________________________________________________________________|
```




Компоненты: Flannel → `kube-flannel`, Envoy Gateway → `envoy-gateway-system`, 
Nginx → `default`, Prometheus → `monitoring`, Fluent Bit → `logging`.



## Список технологий и версий

| Компонент | Версия |
|---|---|
| Ubuntu | 24.04 LTS |
| Kubernetes | v1.30.14 (kubeadm) |
| containerd | 1.7.x (из Ubuntu 24.04) |
| Flannel CNI | v0.28.9 |
| Nginx | stable-alpine |
| Envoy Gateway | v1.1.0 |
| Prometheus | v2.55.0 |
| Fluent Bit | v3.1.0 |
| Docker (для доставки образов) | 26.x |


## Требования к среде

- **ОС:** Ubuntu Server 24.04 LTS (чистая установка)
- **CPU:** 4 ядра
- **RAM:** 8 ГБ
- **Диск:** 40 ГБ
- **Сеть:** интернет для установки пакетов и (при наличии) скачивания образов
- **Права:** root/sudo



## Быстрый старт

Полное развёртывание одной командой:



```bash
git clone https://github.com/Parkinsone/main.git

cd main

chmod +x *.sh

sudo ./setup.sh
```


Или можно использовать Makefile ( Если он предварительно скачен)

make install    # установка K8s
make cluster    # создание кластера
make preload    # доставка образов
make deploy     # развёртывание
make verify     # проверка


## Пошаговая инструкция по развёртыванию

###  Шаг 0. Клонирование репозитория

```bash
git clone https://github.com/Parkinsone/main.git
cd main
chmod +x *.sh
```

### Шаг 1. Подготовка ОС

```bash
./install.sh
```

`install.sh`:
- обновляет систему
- отключает swap
- настраивает модули ядра и sysctl
- ставит containerd с зеркалом Docker Hub
- ставит Docker (для доставки образов)
- ставит kubeadm/kubelet/kubectl v1.30
- отключает ufw

### Шаг 2. Создание кластера

```bash
./init-cluster.sh
```

init-cluster.sh:
- создаёт кластер через `kubeadm init`
- настраивает `~/.kube/config`
- снимает taint с control-plane
- ставит Flannel CNI
- ждёт готовности ноды

**Проверка:**

```bash
kubectl get nodes
```

Ждём: user Ready control-plane


### Шаг 3. Доставка образов (если Docker Hub недоступен)

Если сеть блокирует Docker Hub — доставьте образы через Docker:

./preload-images.sh 
  nginx:stable-alpine 
  envoyproxy/gateway:v1.1.0 
  envoyproxy/envoy:distroless-v1.31.0 
  prom/prometheus:v2.55.0 
  fluent/fluent-bit:3.1.0

Если Docker Hub доступен напрямую — этот шаг **можно пропустить**, kubelet сам скачает образы.

### Шаг 4. Развёртывание решения

```bash
./deploy.sh
```

`deploy.sh` разворачивает:
- Nginx (ConfigMap + Deployment + Service)
- Envoy Gateway (CRD + контроллер + GatewayClass + Gateway + HTTPRoute)
- Prometheus (namespace + RBAC + ConfigMap + Deployment + Service)
- Fluent Bit (namespace + RBAC + ConfigMap + DaemonSet)

## Проверка работоспособности

### Проверьте приложение

```bash
kubectl exec -n default deploy/nginx -- curl -s http://localhost/
```

Ждём: Hello World!


# Проверка мониторинга (Prometheus)

Можно через скрипт:

```bash
./check-metrics.sh
```

Скрипт выводит все метрики с цветовой индикацией (✓/⚠/✗).


**Одной командой (без port-forward):**

```bash
kubectl exec -n monitoring deploy/prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=up' | python3 -m json.tool
```

Ожидаемый вывод: 2 targets со значением `"1"` (UP):
- `job="prometheus"` — метрики самого Prometheus
- `job="envoy-gateway"` — метрики контроллера Envoy Gateway

### Альтернатива: проброс порта Prometheus

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

## В другом терминале:

```bash
curl -s http://localhost:9090/-/healthy
```

Ждём: Prometheus Server is Healthy.

```bash
curl -s 'http://localhost:9090/api/v1/query?query=up' | python3 -m json.tool
```

Ждём: 2 targets со значением "1" (prometheus, envoy-gateway)

# Проверка логирования (Fluent Bit)

**Красивый вывод через скрипт:**

```bash
./check-logs.sh       # последние 20 пользовательских записей (без kube-probe)
```

или

```bash
./check-logs.sh 50       # последние 50
```

или

```bash
./check-logs.sh 50 all       # включая kube-probe (liveness/readiness пробы)
```

### Сделать запрос к Nginx

```bash
kubectl exec -n default deploy/nginx -- curl -s http://localhost/
```

### Посмотреть логи Fluent Bit

```bash
kubectl logs -n logging -l app=fluent-bit --tail=20
```

Ждём: JSON с полем "log" → "GET / HTTP/1.1" 200


## Использованные ресурсы Gateway API

- **GatewayClass** `eg` — класс шлюза (контроллер: `gateway.envoyproxy.io/gatewayclass-controller`)
- **Gateway** `eg` (ns: default) — слушатель HTTP на порту 80
- **HTTPRoute** `nginx` (ns: default) — маршрут `PathPrefix /` → Service `nginx:80`

## Известные ограничения

1. **Single-node кластер.** Control-plane и workload на одной ноде (taint снят). Для продакшна — минимум 3 ноды.
2. **NodePort вместо LoadBalancer.** Из-за отсутствия MetalLB/облачного LB, Gateway опубликован через NodePort.
3. **Доставка образов.** В сетях с блокировкой Docker Hub используется `preload-images.sh` (Docker + `ctr import`). В обычных сетях образы тянутся автоматически.
4. **Prometheus без persistent volume.** Данные теряются при пересоздании pod'а. 
5. **Логи в stdout.** Fluent Bit пишет в stdout pod'а. Для централизованного хранения нужно добавить output 




## CI/CD

### Continuous Integration (CI)

Настроен **GitHub Actions workflow** — файл `.github/workflows/validate.yml`.

**Что делает:**

| Этап | Инструмент | Проверяет |
|---|---|---|
| Валидация YAML | `kubeconform` | Все манифесты в `manifests/` и `gateway/` |
| Валидация bash | `bash -n` | Синтаксис всех `.sh` скриптов |

**Когда запускается:**
- При каждом `git push` в ветку `main`
- При создании pull request в `main`


**Флаги `kubeconform`:**
- `-strict` — строгая проверка
- `-ignore-missing-schemas` — пропускает CRD без схемы (GatewayClass, Gateway, HTTPRoute из Gateway API)
- `-ignore-filename-pattern 'install.yaml'` — исключает большой манифест Envoy Gateway (2 МБ)

**Результат CI:** [https://github.com/Parkinsone/main/actions](https://github.com/Parkinsone/main/actions)

![Validate YAML](https://github.com/Parkinsone/main/actions/workflows/validate.yml/badge.svg)

### Continuous Deployment (CD)

Настроен **автоматический деплой через cron** на VM с кластером.

**Как работает:**

```
┌─────────────────────────────────────────────────────────────┐
│  Каждые 5 минут на VM запускается auto-deploy.sh            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
              git fetch origin main
                              │
                ┌─────────────┴──────────────┐
                │                            │
        Есть новые коммиты?           Изменений нет
                │                            │
              Да                             └───► выход (тихий)
                │
                ▼
         git pull origin main
                │
                ▼
      kubectl apply -f manifests/app/
      kubectl apply -f manifests/monitoring/
      kubectl apply -f manifests/logging/
      kubectl apply -f gateway/gatewayclass.yaml
      kubectl apply -f gateway/gateway.yaml
      kubectl apply -f gateway/httproute.yaml
                │
                ▼
        Логи → /var/log/auto-deploy.log
```

**Файлы:**

| Файл | Назначение |
|---|---|
| `auto-deploy.sh` | Проверяет git и применяет манифесты |
| `install-cd.sh` | Устанавливает cron-задачу автоматически |
| `/var/log/auto-deploy.log` | Логи запусков |

**Установка (автоматическая):**

```bash
./install-cd.sh
```

`install-cd.sh` идемпотентен — если cron-задача уже есть, повторная установка не создаёт дубликат. Скрипт:

1. Проверяет наличие `auto-deploy.sh` и делает его исполняемым
2. Устанавливает пакет `cron`, если его нет
3. Создаёт лог-файл `/var/log/auto-deploy.log` с нужными правами
4. Добавляет cron-задачу:
   ```
   */5 * * * * cd /rep && ./auto-deploy.sh >> /var/log/auto-deploy.log 2>&1
   ```

**Проверка работы:**

```yaml
# 1. Cron-задача установлена
crontab -l
# Ожидаемо:
# */5 * * * * cd /rep && ./auto-deploy.sh >> /var/log/auto-deploy.log 2>&1

# 2. Ручной запуск (не ждать 5 минут)
./auto-deploy.sh

# 3. Посмотреть логи
tail -20 /var/log/auto-deploy.log

# 4. Следить в реальном времени
tail -f /var/log/auto-deploy.log
```


**Ограничения CD:**

- **Задержка до 5 минут.** Cron не реагирует мгновенно. Для мгновенного деплоя нужны GitHub webhooks (требуют публичный IP) или self-hosted runner.
- **Работает только на той VM, где развёрнут кластер.** Не подходит для multi-node без дополнительной настройки.
- **Логи не ротируются.** Со временем `/var/log/auto-deploy.log` растёт. Для продакшна нужен logrotate.
- **Нет отката.** Если `kubectl apply` провалится — старая версия останется. Для автоматического отката нужен ArgoCD/Flux.

### Структура CI/CD

```
.github/
└── workflows/
    └── validate.yml       # CI: kubeconform + bash -n

install-cd.sh              # Устанавливает cron-задачу
auto-deploy.sh             # Cron-задача: git pull + kubectl apply
/var/log/auto-deploy.log   # Логи CD 
```

### Дополнительные улучшения CI/CD

Возможные доработки (не реализованы, но применимы):

1. **Smoke-тест в CI** — разворачивать приложение на `kind` в GitHub Actions и проверять `curl`
2. **Сборка Docker-образов** — если появится своё приложение с Dockerfile
3. **Уведомления в Telegram/Slack** — при успехе/провале CD
4. **Self-hosted runner** — мгновенный деплой при push
5. **ArgoCD** — GitOps с визуальным UI и автоматическим откатом
6. **Logrotate** для `/var/log/auto-deploy.log` — если накопится большой файл


