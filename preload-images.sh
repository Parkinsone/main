#!/usr/bin/env bash
# preload-images.sh — доставляет образ через Docker и импортирует в containerd
# Использование: ./preload-images.sh nginx:stable-alpine
set -euo pipefail

if [ $# -eq 0 ]; then
  echo "Использование: $0 <image1:tag> [image2:tag ...]"
  echo "Пример: $0 nginx:stable-alpine prom/prometheus:v2.55.0"
  exit 1
fi

for IMAGE in "$@"; do
  echo ""
  echo "=================================================="
  echo "===> Обрабатываю: $IMAGE"
  echo "=================================================="

  echo "===> [1/3] Скачиваю через Docker..."
  sudo docker pull "$IMAGE"

  SAFE_NAME=$(echo "$IMAGE" | tr ':/' '__')
  TAR="/tmp/${SAFE_NAME}.tar"

  echo "===> [2/3] Сохраняю в $TAR..."
  sudo docker save "$IMAGE" -o "$TAR"

  echo "===> [3/3] Импортирую в containerd..."
  sudo ctr -n k8s.io images import "$TAR"
  sudo rm -f "$TAR"

  echo "OK: $IMAGE импортирован."
done

echo ""
echo "=================================================="
echo "Все образы импортированы. Текущие образы в containerd:"
sudo crictl images | grep -E "IMAGE|nginx|envoy|prom|fluent"

