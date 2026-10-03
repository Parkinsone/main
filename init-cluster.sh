#!/usr/bin/env bash
# init-cluster.sh — создаёт кластер через kubeadm и ставит Flannel CNI
set -euo pipefail

cd "$(dirname "$0")"

# ---------- 1. kubeadm init ----------
if [ -f /etc/kubernetes/admin.conf ]; then
  echo "[1/4] Кластер уже инициализирован, пропускаю kubeadm init."
else
  echo "[1/4] Инициализация кластера kubeadm..."
  sudo kubeadm init --pod-network-cidr=192.168.0.0/16
fi

# ---------- 2. kubectl config ----------
echo "[2/4] Настройка kubectl для пользователя $USER..."
mkdir -p "$HOME/.kube"
sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

# ---------- 3. Снять taint с control-plane ----------
echo "[3/4] Снятие taint с control-plane (single-node)..."
kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true

# ---------- 4. Flannel ----------
echo "[4/4] Установка Flannel CNI..."
if [ ! -f kube-flannel.yml ]; then
  echo "Скачиваю манифест Flannel..."
  curl -fL -o kube-flannel.yml \
    https://cdn.jsdelivr.net/gh/flannel-io/flannel@master/Documentation/kube-flannel.yml
  sed -i 's|10.244.0.0/16|192.168.0.0/16|g' kube-flannel.yml
fi

# Применяем только оригинальный манифест (не dockerhub-версию)
kubectl apply -f kube-flannel.yml

# ---------- Ожидание Ready ----------
echo "Ожидание готовности ноды (до 3 минут)..."
for i in $(seq 1 36); do
  STATUS=$(kubectl get node -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
  if [ "$STATUS" = "True" ]; then
    echo ""
    echo "=================================================="
    echo "Кластер готов!"
    echo "=================================================="
    kubectl get nodes
    kubectl get pods -A
    exit 0
  fi
  sleep 5
done

echo ""
echo "ОШИБКА: нода не стала Ready за 3 минуты."
echo "Проверьте: kubectl describe node"
kubectl get nodes
kubectl get pods -A
exit 11~#!/usr/bin/env bash
# init-cluster.sh — создаёт кластер через kubeadm и ставит Flannel CNI
set -euo pipefail

cd "$(dirname "$0")"

# ---------- 1. kubeadm init ----------
if [ -f /etc/kubernetes/admin.conf ]; then
  echo "[1/4] Кластер уже инициализирован, пропускаю kubeadm init."
else
  echo "[1/4] Инициализация кластера kubeadm..."
  sudo kubeadm init --pod-network-cidr=192.168.0.0/16
fi

# ---------- 2. kubectl config ----------
echo "[2/4] Настройка kubectl для пользователя $USER..."
mkdir -p "$HOME/.kube"
sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

# ---------- 3. Снять taint с control-plane ----------
echo "[3/4] Снятие taint с control-plane (single-node)..."
kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true

# ---------- 4. Flannel ----------
echo "[4/4] Установка Flannel CNI..."
if [ ! -f kube-flannel.yml ]; then
  echo "Скачиваю манифест Flannel..."
  curl -fL -o kube-flannel.yml \
    https://cdn.jsdelivr.net/gh/flannel-io/flannel@master/Documentation/kube-flannel.yml
  sed -i 's|10.244.0.0/16|192.168.0.0/16|g' kube-flannel.yml
fi

# Применяем только оригинальный манифест (не dockerhub-версию)
kubectl apply -f kube-flannel.yml

# ---------- Ожидание Ready ----------
echo "Ожидание готовности ноды (до 3 минут)..."
for i in $(seq 1 36); do
  STATUS=$(kubectl get node -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
  if [ "$STATUS" = "True" ]; then
    echo ""
    echo "=================================================="
    echo "Кластер готов!"
#!/usr/bin/env bash
# init-cluster.sh — создаёт кластер через kubeadm и ставит Flannel CNI
set -euo pipefail

cd "$(dirname "$0")"

# ---------- 1. kubeadm init ----------
if [ -f /etc/kubernetes/admin.conf ]; then
  echo "[1/4] Кластер уже инициализирован, пропускаю kubeadm init."
else
  echo "[1/4] Инициализация кластера kubeadm..."
  sudo kubeadm init --pod-network-cidr=192.168.0.0/16
fi

# ---------- 2. kubectl config ----------
echo "[2/4] Настройка kubectl для пользователя $USER..."
mkdir -p "$HOME/.kube"
sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

# ---------- 3. Снять taint с control-plane ----------
echo "[3/4] Снятие taint с control-plane (single-node)..."
kubectl taint nodes --all node-role.kubernetes.io/control-plane- 2>/dev/null || true

# ---------- 4. Flannel ----------
echo "[4/4] Установка Flannel CNI..."
if [ ! -f kube-flannel.yml ]; then
  echo "Скачиваю манифест Flannel..."
  curl -fL -o kube-flannel.yml \
    https://cdn.jsdelivr.net/gh/flannel-io/flannel@master/Documentation/kube-flannel.yml
  sed -i 's|10.244.0.0/16|192.168.0.0/16|g' kube-flannel.yml
fi

# Применяем только оригинальный манифест (не dockerhub-версию)
kubectl apply -f kube-flannel.yml
# ---------- Ожидание Ready ----------
echo "Ожидание готовности ноды (до 3 минут)..."
for i in $(seq 1 36); do
  STATUS=$(kubectl get node -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "")
  if [ "$STATUS" = "True" ]; then
    echo ""
    echo "=================================================="
    echo "Кластер готов!"
    echo "=================================================="
    kubectl get nodes
    kubectl get pods -A
    exit 0
  fi
  sleep 5
done

echo ""
echo "ОШИБКА: нода не стала Ready за 3 минуты."
echo "Проверьте: kubectl describe node"
kubectl get nodes
kubectl get pods -A
exit 1
