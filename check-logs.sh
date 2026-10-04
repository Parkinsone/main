#!/usr/bin/env bash
# check-logs.sh — красивый вывод логов из Fluent Bit
# Использование:
#   ./check-logs.sh              — последние 20 пользовательских записей
#   ./check-logs.sh 50           — последние 50 пользовательских записей
#   ./check-logs.sh 50 all       — включая kube-probe
set -uo pipefail

# ---------- Цвета ----------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ---------- Параметры ----------
LIMIT="${1:-20}"
FILTER="${2:-user}"
RAW_TAIL=1000

# ---------- Проверка окружения ----------
if ! kubectl get daemonset -n logging fluent-bit &>/dev/null; then
  echo -e "${RED}ОШИБКА: Fluent Bit не найден в namespace 'logging'${NC}"
  exit 1
fi

POD=$(kubectl get pod -n logging -l app=fluent-bit \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

# ---------- Заголовок ----------
echo ""
echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${CYAN}  ЛОГИ FLUENT BIT${NC}"
echo -e "${BOLD}${CYAN}══════════════════════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  Pod:        ${BOLD}${POD}${NC}"
echo -e "  Namespace:  ${BOLD}logging${NC}"
echo -e "  Показано:   последние ${BOLD}${LIMIT}${NC} записей (после фильтрации)"
echo -e "  Фильтр:     ${BOLD}${FILTER}${NC}   ${DIM}(user = без kube-probe, all = всё)${NC}"
echo -e "  Время:      ${BOLD}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo ""

# ---------- Получить логи во временный файл ----------
TMPLOG=$(mktemp)
trap "rm -f $TMPLOG" EXIT

kubectl logs -n logging "$POD" --tail="$RAW_TAIL" 2>/dev/null | grep '^{' > "$TMPLOG" || true

if [ ! -s "$TMPLOG" ]; then
  echo -e "  ${YELLOW}Логов нет.${NC} Сделайте запрос к приложению:"
  echo "    kubectl exec -n default deploy/nginx -- curl -s http://localhost/"
  exit 0
fi

# ---------- Парсинг ----------
export LOGFILE="$TMPLOG"
export FILTER_VALUE="$FILTER"
export LIMIT_VALUE="$LIMIT"
export RAW_TAIL_VALUE="$RAW_TAIL"

python3 << 'PYEOF'
import os, json
from datetime import datetime

LOGFILE  = os.environ.get('LOGFILE')
FILTER   = os.environ.get('FILTER_VALUE', 'user')
LIMIT    = int(os.environ.get('LIMIT_VALUE', '20'))
RAW_TAIL = int(os.environ.get('RAW_TAIL_VALUE', '1000'))

GREEN   = '\033[0;32m'
RED     = '\033[0;31m'
YELLOW  = '\033[1;33m'
CYAN    = '\033[0;36m'
BLUE    = '\033[0;34m'
MAGENTA = '\033[0;35m'
BOLD    = '\033[1m'
DIM     = '\033[2m'
NC      = '\033[0m'

# Читаем файл
records = []
with open(LOGFILE) as f:
    for line in f:
        line = line.strip()
        if not line or not line.startswith('{'):
            continue
        try:
            d = json.loads(line)
        except Exception:
            continue

        log_line = d.get('log', '')
        if FILTER == 'user' and 'kube-probe' in log_line:
            continue

        records.append((d, log_line))

# Берём последние LIMIT
records = records[-LIMIT:]

if not records:
    print(f'  {YELLOW}Записей с фильтром "{FILTER}" не найдено.{NC}')
    print()
    print(f'  {DIM}Возможные причины:{NC}')
    print(f'  {DIM}  1. Не было запросов за последнее время{NC}')
    print(f'  {DIM}  2. Fluent Bit ещё не сбросил буфер (flush раз в 5 сек){NC}')
    print(f'  {DIM}  3. Запрос был давно, за пределами {RAW_TAIL} строк{NC}')
    print()
    print(f'  {DIM}Попробуйте: kubectl exec -n default deploy/nginx -- curl -s http://localhost/{NC}')
    print(f'  {DIM}Затем:      sleep 8 && ./check-logs.sh 20 user{NC}')
    raise SystemExit(0)

for idx, (d, log_line) in enumerate(records, 1):
    k8s       = d.get('kubernetes', {}) or {}
    pod       = k8s.get('pod_name', '?')
    ns        = k8s.get('namespace_name', '?')
    container = k8s.get('container_name', '?')
    date_epoch = d.get('date', 0)

    try:
        t = datetime.fromtimestamp(date_epoch).strftime('%H:%M:%S')
    except Exception:
        t = '--:--:--'

    http_code = '???'
    code_color = CYAN
    if '" 200 ' in log_line:
        http_code, code_color = '200', GREEN
    elif '" 404 ' in log_line:
        http_code, code_color = '404', YELLOW
    elif '" 5' in log_line:
        http_code, code_color = '5xx', RED
    elif '" 3' in log_line:
        http_code, code_color = '3xx', BLUE

    client = '?'
    if 'kube-probe' in log_line:
        client = 'kube-probe'
    elif 'curl' in log_line:
        client = 'curl'
    elif 'wget' in log_line:
        client = 'wget'

    method = '?'
    path = '?'
    for m in ['GET', 'POST', 'PUT', 'DELETE', 'HEAD']:
        marker = '"' + m + ' '
        if marker in log_line:
            method = m
            try:
                start = log_line.index(marker) + len(marker)
                end = log_line.index(' ', start)
                path = log_line[start:end]
            except Exception:
                pass
            break

    print(f'  {DIM}#{idx:03d}{NC}  {BOLD}{t}{NC}  {code_color}{http_code}{NC}  {BOLD}{method:6}{NC}  {CYAN}{path}{NC}')
    print(f'         {DIM}pod={NC}{MAGENTA}{pod}{NC}  {DIM}ns={NC}{ns}  {DIM}container={NC}{container}  {DIM}client={NC}{client}')

print()
print(f'  {BOLD}Всего записей:{NC} {len(records)} (из {RAW_TAIL} последних сырых строк)')
PYEOF

echo ""
