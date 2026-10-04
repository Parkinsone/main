#!/usr/bin/env bash
# check-metrics.sh — красивая проверка метрик Prometheus
set -uo pipefail

# ---------- Цвета ----------
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ---------- Функции ----------
header() {
  echo ""
  echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${CYAN}  $*${NC}"
  echo -e "${BOLD}${CYAN}═══════════════════════════════════════════════════════${NC}"
}

section() {
  echo ""
  echo -e "${BOLD}▶ $*${NC}"
  echo "───────────────────────────────────────────────────────"
}

# Запрос к Prometheus API (внутри пода)
prom_query() {
  local query="$1"
  kubectl exec -n monitoring deploy/prometheus -- \
    wget -qO- "http://localhost:9090/api/v1/query?query=${query}" 2>/dev/null
}

# Извлечь значение из JSON ответа Prometheus (использует python3)
extract_value() {
  python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if data.get('status') != 'success':
        print('ERROR')
        sys.exit(0)
    result = data['data']['result']
    if not result:
        print('N/A')
    else:
        print(result[0]['value'][1])
except Exception:
    print('PARSE_ERROR')
"
}

# Проверка метрики: имя, query, описание, ожидание
check_metric() {
  local name="$1"
  local query="$2"
  local desc="$3"

  local raw
  raw=$(prom_query "$query")
  local value
  value=$(echo "$raw" | extract_value)

  if [ "$value" = "ERROR" ] || [ "$value" = "PARSE_ERROR" ]; then
    printf "  ${RED}✗${NC} %-45s ${RED}ОШИБКА${NC}\n" "$name"
    printf "    %s\n" "$desc"
  elif [ "$value" = "N/A" ]; then
    printf "  ${YELLOW}⚠${NC} %-45s ${YELLOW}нет данных${NC}\n" "$name"
    printf "    %s\n" "$desc"
  else
    printf "  ${GREEN}✓${NC} %-45s ${BOLD}%-15s${NC}\n" "$name" "$value"
    printf "    ${YELLOW}→${NC} %s\n" "$desc"
  fi
}

# ---------- Проверка окружения ----------
if ! kubectl get deployment -n monitoring prometheus &>/dev/null; then
  echo -e "${RED}ОШИБКА: Prometheus не найден в namespace 'monitoring'${NC}"
  echo "Убедитесь, что вы в /rep и решение развёрнуто:"
  echo "  kubectl get pods -n monitoring"
  exit 1
fi

POD=$(kubectl get pod -n monitoring -l app=prometheus \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

header "ПРОВЕРКА МЕТРИК PROMETHEUS"
echo ""
echo -e "  Prometheus Pod:  ${BOLD}${POD}${NC}"
echo -e "  Namespace:       ${BOLD}monitoring${NC}"
echo -e "  Время:           ${BOLD}$(date '+%Y-%m-%d %H:%M:%S')${NC}"

# ---------- 1. Targets ----------
section "1. АКТИВНЫЕ TARGETS (query: up)"

TARGETS_JSON=$(prom_query 'up')

# Разбор targets
python3 <<EOF
import sys, json
raw = '''$TARGETS_JSON'''
try:
    data = json.loads(raw)
except Exception:
    print("  Ошибка разбора ответа")
    sys.exit(0)

result = data.get('data', {}).get('result', [])
if not result:
    print("  Нет активных targets")
    sys.exit(0)

for r in result:
    job = r['metric'].get('job', '?')
    instance = r['metric'].get('instance', '?')
    value = r['value'][1]
    if value == '1':
        print(f"  \033[0;32m✓\033[0m  {job:20} \033[1;32mUP\033[0m    {instance}")
    else:
        print(f"  \033[0;31m✗\033[0m  {job:20} \033[1;31mDOWN\033[0m  {instance}")
EOF

# ---------- 2. Метрики Prometheus ----------
section "2. МЕТРИКИ PROMETHEUS (self-monitoring)"

check_metric \
  "prometheus_build_info" \
  "prometheus_build_info" \
  "Версия Prometheus"

check_metric \
  "prometheus_tsdb_head_series" \
  "prometheus_tsdb_head_series" \
  "Количество временных рядов в памяти"

check_metric \
  "scrape_samples_scraped{prometheus}" \
  'scrape_samples_scraped{job="prometheus"}' \
  "Метрик собрано с Prometheus за последний scrape"

check_metric \
  "scrape_samples_scraped{envoy}" \
  'scrape_samples_scraped{job="envoy-gateway"}' \
  "Метрик собрано с Envoy Gateway за последний scrape"

check_metric \
  "scrape_duration_seconds" \
  'scrape_duration_seconds{job="prometheus"}' \
  "Время scrape Prometheus (секунды)"

# ---------- 3. Метрики Envoy Gateway: Go runtime ----------
section "3. ENVOY GATEWAY — Go runtime"

check_metric \
  "go_goroutines" \
  'go_goroutines{job="envoy-gateway"}' \
  "Количество горутин контроллера"

check_metric \
  "go_memstats_alloc_bytes" \
  'go_memstats_alloc_bytes{job="envoy-gateway"}' \
  "Выделенная память (bytes)"

check_metric \
  "process_resident_memory_bytes" \
  'process_resident_memory_bytes{job="envoy-gateway"}' \
  "Потребление RAM (bytes)"

check_metric \
  "process_cpu_seconds_total" \
  'process_cpu_seconds_total{job="envoy-gateway"}' \
  "CPU-время процесса (секунды)"

# ---------- 4. Метрики Envoy Gateway: controller-runtime ----------
section "4. ENVOY GATEWAY — controller-runtime"

check_metric \
  "controller_runtime_reconcile_total" \
  'controller_runtime_reconcile_total{job="envoy-gateway"}' \
  "Всего reconcile-циклов (обработок ресурсов)"

check_metric \
  "controller_runtime_reconcile_errors_total" \
  'controller_runtime_reconcile_errors_total{job="envoy-gateway"}' \
  "Ошибки reconcile"

check_metric \
  "controller_runtime_active_workers" \
  'controller_runtime_active_workers{job="envoy-gateway"}' \
  "Активные воркеры"

check_metric \
  "controller_runtime_max_concurrent_reconciles" \
  'controller_runtime_max_concurrent_reconciles{job="envoy-gateway"}' \
  "Максимум параллельных reconcile"

# ---------- Итог ----------
header "ИТОГ"

TOTAL_UP=$(echo "$TARGETS_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
r = d.get('data', {}).get('result', [])
print(sum(1 for x in r if x['value'][1] == '1'))
" 2>/dev/null || echo "?")

echo ""
echo -e "  Всего targets UP: ${BOLD}${GREEN}${TOTAL_UP}${NC}"
echo ""
echo -e "  ${YELLOW}Подсказка:${NC} если какой-то target DOWN — проверьте его доступность:"
echo "    kubectl exec -n <namespace> <pod> -- wget -qO- http://<target>/metrics"
echo ""
