#!/usr/bin/env bash
# deploy.sh — разворачивает всё решение в уже существующем кластере
set -euo pipefail

cd "$(dirname "$0")"

log() { echo ""; echo "===> $*"; }

# ------------------------------------------------------------
# 1. Nginx (приложение)
# ------------------------------------------------------------
log "[1/5] Разворачиваю Nginx..."
kubectl apply -f manifests/app/

# ------------------------------------------------------------
# 2. Envoy Gateway (контроллер + CRD)
# ------------------------------------------------------------
log "[2/5] Устанавливаю Envoy Gateway..."
if ! kubectl get deployment -n envoy-gateway-system envoy-gateway &>/dev/null; then
  kubectl apply --server-side -f gateway/install.yaml
else
  echo "Envoy Gateway уже установлен, пропускаю."
fi

log "Жду готовности контроллера Envoy Gateway (до 180 сек)..."
kubectl wait --for=condition=Available deployment/envoy-gateway \
  -n envoy-gateway-system --timeout=180s

# ------------------------------------------------------------
# 3. Gateway API ресурсы
# ------------------------------------------------------------
log "[3/5] Создаю GatewayClass / Gateway / HTTPRoute..."

# Сначала GatewayClass
kubectl apply -f gateway/gatewayclass.yaml

# EnvoyProxy с NodePort (если есть)
if [ -f gateway/envoyproxy.yaml ]; then
  kubectl apply -f gateway/envoyproxy.yaml
fi

# Gateway и HTTPRoute
kubectl apply -f gateway/gateway.yaml
kubectl apply -f gateway/httproute.yaml

# ------------------------------------------------------------
# 4. Prometheus
# ------------------------------------------------------------
log "[4/5] Разворачиваю Prometheus..."
kubectl apply -f manifests/monitoring/namespace.yaml
sleep 3
kubectl apply -f manifests/monitoring/

# ------------------------------------------------------------
# 5. Fluent Bit
# ------------------------------------------------------------
log "[5/5] Разворачиваю Fluent Bit..."
kubectl apply -f manifests/logging/namespace.yaml
sleep 3
kubectl apply -f manifests/logging/

# ------------------------------------------------------------
# Ожидание готовности
# ------------------------------------------------------------
log "Жду готовности основных pod'ов (до 180 сек)..."

kubectl wait --for=condition=Ready pod -l app=nginx -n default --timeout=120s || true
kubectl wait --for=condition=Ready pod -l app=prometheus -n monitoring --timeout=120s || true
kubectl wait --for=condition=Ready pod -l app=fluent-bit -n logging --timeout=120s || true

# ------------------------------------------------------------
# Итог
# ------------------------------------------------------------
log "Состояние развёрнутого решения:"

echo ""
echo "--- Pods ---"
kubectl get pods -n default
kubectl get pods -n envoy-gateway-system
kubectl get pods -n monitoring
kubectl get pods -n logging

echo ""
echo "--- Gateway API ---"
kubectl get gateway,httproute -n default

echo ""
echo "--- Envoy Service (NodePort) ---"
NODEPORT=$(kubectl get svc -n envoy-gateway-system \
  -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].spec.ports[0].nodePort}' 2>/dev/null || echo "?")

echo ""
echo "=================================================="
echo "ГОТОВО!"
echo ""
echo "Проверка приложения:"
echo "  curl http://<node-ip>:${NODEPORT}/"
echo "  (или) kubectl exec -n default deploy/nginx -- curl -s http://localhost/"
echo ""
echo "Проверка мониторинга:"
echo "  kubectl port-forward -n monitoring svc/prometheus 9090:9090"
echo "  curl -s 'http://localhost:9090/api/v1/query?query=up'"
echo ""
echo "Проверка логирования:"
echo "  kubectl logs -n logging -l app=fluent-bit --tail=20"
echo "=================================================="
