#!/usr/bin/env bash
# install.sh — готовит Ubuntu 24.04 к установке Kubernetes (kubeadm)
set -euo pipefail

echo "[1/8] Обновление системы..."
sudo apt update && sudo apt upgrade -y

echo "[2/8] Отключение swap..."
sudo swapoff -a
sudo sed -i '/swap.img/ s/^/#/' /etc/fstab

echo "[3/8] Модули ядра и sysctl..."
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
sudo sysctl --system

echo "[4/8] Установка containerd..."
sudo apt install -y containerd
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

echo "[5/8] Настройка зеркала Docker Hub (для обхода блокировок)..."
sudo mkdir -p /etc/containerd/certs.d/docker.io
sudo tee /etc/containerd/certs.d/docker.io/hosts.toml <<'EOF'
server = "https://docker.io"

[host."https://dockerhub.timeweb.cloud"]
  capabilities = ["pull", "resolve"]

[host."https://huecker.io"]
  capabilities = ["pull", "resolve"]

[host."https://docker.m.daocloud.io"]
  capabilities = ["pull", "resolve"]
EOF

# Включаем config_path в секции CRI
sudo sed -i "s|config_path = ''|config_path = '/etc/containerd/certs.d'|" /etc/containerd/config.toml

# Проверка валидности
if ! sudo containerd config dump > /dev/null 2>&1; then
  echo "ОШИБКА: конфиг containerd битый. Проверьте /etc/containerd/config.toml"
  exit 1
fi

sudo systemctl restart containerd
sudo systemctl enable containerd

echo "[6/8] Установка Docker (для доставки образов через preload-images.sh)..."
if ! command -v docker &>/dev/null; then
  sudo apt install -y docker.io
  sudo systemctl enable --now docker
  # Зеркало для Docker
  sudo mkdir -p /etc/docker
  sudo tee /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": [
    "https://dockerhub.timeweb.cloud",
    "https://huecker.io",
    "https://docker.m.daocloud.io"
  ]
}
EOF
  sudo systemctl restart docker
fi

echo "[7/8] Установка kubeadm / kubelet / kubectl v1.30..."
sudo apt install -y apt-transport-https ca-certificates curl gpg
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | \
  sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

echo "[8/8] Отключение firewall..."
sudo ufw disable || true

echo ""
echo "=================================================="
echo "Подготовка завершена."
echo ""
echo "Следующий шаг — создание кластера:"
echo "  ./init-cluster.sh"
echo "=================================================="
