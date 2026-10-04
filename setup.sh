#!/usr/bin/env bash
# setup.sh — полное развёртывание решения с нуля
set -euo pipefail

cd "$(dirname "$0")"

log() { echo ""; echo "========================================"; echo "===> $*"; echo "========================================"; }

# ---------- Проверка: root ----------
if [ "$EUID" -ne 0 ]; then
  echo "Запустите через sudo: sudo ./setup.sh"
  exit 1
fi

log "ЭТАП 1/5: Подготовка ОС и установка Kubernetes"
./install.sh

log "ЭТАП 2/5: Создание кластера и установка CNI"
# init-cluster.sh запускается от пользователя, но kubectl-конфиг пишет в $HOME
sudo -u "$SUDO_USER" -H ./init-cluster.sh

log "ЭТАП 3/5: Доставка образов через Docker"
./preload-images.sh \
  nginx:stable-alpine \
  envoyproxy/gateway:v1.1.0 \
  envoyproxy/envoy:distroless-v1.31.0 \
  prom/prometheus:v2.55.0 \
  fluent/fluent-bit:3.1.0

log "ЭТАП 4/5: Развёртывание всех компонентов"
sudo -u "$SUDO_USER" -H ./deploy.sh

log "ЭТАП 5/5: Финальная проверка"
echo ""
echo "--- Поды ---"
kubectl get pods -A | grep -vE "Running|Completed" || echo "Все поды Running"

echo ""
echo "--- Gateway ---"
kubectl get gateway,httproute -n default

echo ""
echo "--- NodePort Envoy ---"
kubectl get svc -n envoy-gateway-system | grep -E "LoadBalancer|NodePort"

NODE_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "========================================"
echo "ГОТОВО!"
echo ""
echo "Проверка приложения:"
echo "  curl http://${NODE_IP}:<NODEPORT>/"
echo ""
echo "Проверка мониторинга:"
echo "  kubectl port-forward -n monitoring svc/prometheus 9090:9090 &"
echo "  curl -s 'http://localhost:9090/api/v1/query?query=up'"
echo ""
echo "Проверка логирования:"
echo "  kubectl logs -n logging -l app=fluent-bit --tail=20"
echo "========================================"
