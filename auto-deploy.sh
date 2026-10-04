#!/usr/bin/env bash
# auto-deploy.sh — CD через cron: git pull + kubectl apply
set -uo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$REPO_DIR"

LOG="/var/log/auto-deploy.log"
TS=$(date '+%Y-%m-%d %H:%M:%S')

log() { echo "[$TS] $*" >> "$LOG"; }

# ---------- 1. Проверка обновлений ----------
git fetch origin main --quiet 2>>"$LOG" || { log "git fetch failed"; exit 1; }

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main)

if [ "$LOCAL" = "$REMOTE" ]; then
  # Ничего не пишем в лог, если изменений нет — иначе лог растёт
  exit 0
fi

log "Обнаружены изменения: $LOCAL → $REMOTE"

# ---------- 2. Pull ----------
git pull origin main --quiet >>"$LOG" 2>&1 || { log "git pull failed"; exit 1; }
log "git pull выполнен"

# ---------- 3. Apply манифестов ----------
# Nginx
kubectl apply -f manifests/app/ >>"$LOG" 2>&1 && log "app OK" || log "app FAILED"

# Gateway API (не трогаем install.yaml — он большой)
kubectl apply -f gateway/gatewayclass.yaml >>"$LOG" 2>&1 && log "gatewayclass OK" || log "gatewayclass FAILED"
kubectl apply -f gateway/gateway.yaml >>"$LOG" 2>&1 && log "gateway OK" || log "gateway FAILED"
kubectl apply -f gateway/httproute.yaml >>"$LOG" 2>&1 && log "httproute OK" || log "httproute FAILED"
[ -f gateway/envoyproxy.yaml ] && kubectl apply -f gateway/envoyproxy.yaml >>"$LOG" 2>&1

# Monitoring
kubectl apply -f manifests/monitoring/ >>"$LOG" 2>&1 && log "monitoring OK" || log "monitoring FAILED"

# Logging
kubectl apply -f manifests/logging/ >>"$LOG" 2>&1 && log "logging OK" || log "logging FAILED"

log "=== Развёртывание завершено ==="
