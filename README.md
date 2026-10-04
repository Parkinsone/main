# Развёртывание веб-приложения в Kubernetes с Gateway API, мониторингом и логированием

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
    Пользователь
         │
         ▼
   ┌──────────────┐
   │   Gateway    │  (NodePort 31996)
   │  (Envoy)     │
   └──────┬───────┘
          │ HTTPRoute → Service nginx:80
          ▼
   ┌──────────────┐         ┌─────────────┐
   │    Nginx     │◄────────│  Prometheus │  (scrape)
   │ (Deployment) │         └─────────────┘
   └──────┬───────┘
          │ access-логи (/var/log/containers)
          ▼
   ┌──────────────┐
   │  Fluent Bit  │  (DaemonSet) → stdout
   └──────────────┘
```

## Список технологий и версий

| Компонент | Версия |
|---|---|
| Ubuntu | 24.04 LTS |
| Kubernetes | v1.30.14 |
| containerd | 1.7.x (из Ubuntu 24.04) |
| Flannel CNI | v0.28.9 |
| Nginx | stable-alpine |
| Envoy Gateway | v1.1.0 |
| Prometheus | v2.55.0 |
| Fluent Bit | v3.1.0 |
| Docker (для доставки образов) | 26.x |

## Быстрый старт

Полное развёртывание одной командой:



Если запускаете от обычного пользователя, у которого есть права sudo — используйте sudo ./setup.sh.



git clone https://github.com/Parkinsone/main.git
cd main
chmod +x *.sh
sudo ./setup.sh



Или можно использовать Makefile ( Если оне предварительно скачен)

make install    # установка K8s
make cluster    # создание кластера
make preload    # доставка образов
make deploy     # развёртывание
make verify     # проверка


## Пошаговая инструкция по развёртыванию

### Шаг 1. Подготовка ОС

git clone https://github.com/Parkinsone/main

cd main

При необходимости
chmod +x install.sh init-cluster.sh deploy.sh preload-images.sh

./install.sh


`install.sh`:
- обновляет систему
- отключает swap
- настраивает модули ядра и sysctl
- ставит containerd с зеркалом Docker Hub
- ставит Docker (для доставки образов)
- ставит kubeadm/kubelet/kubectl v1.30
- отключает ufw

### Шаг 2. Создание кластера

./init-cluster.sh

init-cluster.sh:
- создаёт кластер через `kubeadm init`
- настраивает `~/.kube/config`
- снимает taint с control-plane
- ставит Flannel CNI
- ждёт готовности ноды

**Проверка:**

kubectl get nodes

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


./deploy.sh

`deploy.sh` разворачивает:
- Nginx (ConfigMap + Deployment + Service)
- Envoy Gateway (CRD + контроллер + GatewayClass + Gateway + HTTPRoute)
- Prometheus (namespace + RBAC + ConfigMap + Deployment + Service)
- Fluent Bit (namespace + RBAC + ConfigMap + DaemonSet)

## Проверка работоспособности

#№№ Проверьте приложение

kubectl exec -n default deploy/nginx -- curl -s http://localhost/

Ждём: Hello World!


### Проверка мониторинга

kubectl exec -n monitoring deploy/prometheus -- \
  wget -qO- 'http://localhost:9090/api/v1/query?query=up' | python3 -m json.tool



### Алтернатива: проброс порта Prometheus
kubectl port-forward -n monitoring svc/prometheus 9090:9090

# В другом терминале:
curl -s http://localhost:9090/-/healthy

Ждём: Prometheus Server is Healthy.

curl -s 'http://localhost:9090/api/v1/query?query=up' | python3 -m json.tool

Ждём: 2 targets со значением "1" (prometheus, envoy-gateway)

### Проверка логирования


### Сделать запрос к Nginx
kubectl exec -n default deploy/nginx -- curl -s http://localhost/

### Посмотреть логи Fluent Bit
kubectl logs -n logging -l app=fluent-bit --tail=20

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

## Структура репозитория

```
.
├── README.md
├── .gitignore
├── install.sh              # подготовка ОС + установка K8s
├── init-cluster.sh         # создание кластера + Flannel
├── deploy.sh               # развёртывание всех компонентов
├── preload-images.sh       # доставка образов через Docker
├── gateway/
│   ├── install.yaml        # CRD + контроллер Envoy Gateway
│   ├── gatewayclass.yaml
│   ├── gateway.yaml
│   ├── httproute.yaml
│   └── envoyproxy.yaml     # NodePort для data plane
└── manifests/
    ├── app/                # Nginx
    ├── monitoring/         # Prometheus
    └── logging/            # Fluent Bit
```
