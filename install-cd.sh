#!/usr/bin/env bash
# install-cd.sh — настраивает автоматический CD через cron
set -euo pipefail

cd "$(dirname "$0")"

REPO_DIR="$(pwd)"
LOG_FILE="/var/log/auto-deploy.log"

echo "===> Настройка CD через cron"

# ---------- 1. Проверка auto-deploy.sh ----------
if [ ! -f "$REPO_DIR/auto-deploy.sh" ]; then
  echo "ОШИБКА: не найден $REPO_DIR/auto-deploy.sh"
  exit 1
fi
chmod +x "$REPO_DIR/auto-deploy.sh"

# ---------- 2. Проверка cron ----------
if ! command -v crontab &>/dev/null; then
  echo "Устанавливаю cron..."
  sudo apt update
  sudo apt install -y cron
  sudo systemctl enable --now cron
fi

# ---------- 3. Создать лог-файл с правами ----------
sudo touch "$LOG_FILE"
sudo chown "$USER:$USER" "$LOG_FILE"
sudo chmod 644 "$LOG_FILE"

# ---------- 4. Добавить cron-задачу (идемпотентно) ----------
CRON_LINE="*/5 * * * * cd $REPO_DIR && ./auto-deploy.sh >> $LOG_FILE 2>&1"

if crontab -l 2>/dev/null | grep -qF "auto-deploy.sh"; then
  echo "  ✓ Cron-задача уже установлена, пропускаю."
else
  (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
  echo "  ✓ Cron-задача добавлена (каждые 5 минут)."
fi

# ---------- 5. Итог ----------
echo ""
echo "=================================================="
echo "CD настроен!"
echo ""
echo "Проверить установку:"
echo "  crontab -l"
echo ""
echo "Логи авто-деплоя:"
echo "  tail -f $LOG_FILE"
echo ""
echo "Проверить вручную (не ждать 5 минут):"
echo "  $REPO_DIR/auto-deploy.sh"
echo "=================================================="
