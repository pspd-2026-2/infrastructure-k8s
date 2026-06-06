#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C

URL="${1:-${TARGET_URL:-http://${GATEWAY_HOST:-api.pspd.local}}}"
REQUESTS="${REQUESTS:-500}"
CONCURRENCY="${CONCURRENCY:-25}"
OUTPUT_DIR="${OUTPUT_DIR:-docs/performance}"
VERSION_LABEL="${VERSION_LABEL:-current}"

mkdir -p "$OUTPUT_DIR"

TS="$(date +"%Y%m%d-%H%M%S")"
RESULT_FILE="$OUTPUT_DIR/load-test-${VERSION_LABEL}-${TS}.csv"
SUMMARY_FILE="$OUTPUT_DIR/load-test-${VERSION_LABEL}-${TS}-summary.txt"
TMP_TIMES="$(mktemp)"

trap 'rm -f "$TMP_TIMES"' EXIT

echo "Teste de carga"
echo "URL: $URL"
echo "Requisições: $REQUESTS"
echo "Concorrência: $CONCURRENCY"
echo "Versão: $VERSION_LABEL"
echo ""

echo "request,status,time_total" > "$RESULT_FILE"

START="$(date +%s.%N)"

# shellcheck disable=SC2016
seq 1 "$REQUESTS" | xargs -I{} -P "$CONCURRENCY" sh -c '
  i="$1"
  url="$2"

  result=$(curl -sS \
    -o /dev/null \
    -w "%{http_code},%{time_total}" \
    --connect-timeout 3 \
    --max-time 10 \
    "$url" 2>/dev/null || echo "000,0")

  printf "%s,%s\n" "$i" "$result"
' sh {} "$URL" >> "$RESULT_FILE"

END="$(date +%s.%N)"

DURATION="$(awk -v start="$START" -v end="$END" 'BEGIN { printf "%.3f", end - start }')"

TOTAL="$(tail -n +2 "$RESULT_FILE" | wc -l)"
SUCCESS="$(awk -F, 'NR > 1 && $2 >= 200 && $2 < 400 { count++ } END { print count + 0 }' "$RESULT_FILE")"
FAILURES="$(awk -v total="$TOTAL" -v success="$SUCCESS" 'BEGIN { print total - success }')"

awk -F, 'NR > 1 && $2 >= 200 && $2 < 400 { print $3 }' "$RESULT_FILE" | sort -n > "$TMP_TIMES"

COUNT_SUCCESS="$(wc -l < "$TMP_TIMES")"

if [ "$COUNT_SUCCESS" -gt 0 ]; then
  AVG="$(awk '{ sum += $1 } END { printf "%.4f", sum / NR }' "$TMP_TIMES")"
  MIN="$(awk 'NR == 1 { printf "%.4f", $1 }' "$TMP_TIMES")"
  MAX="$(awk 'END { printf "%.4f", $1 }' "$TMP_TIMES")"

  P50_INDEX=$(( (COUNT_SUCCESS + 1) / 2 ))
  P95_INDEX=$(( (COUNT_SUCCESS * 95 + 99) / 100 ))

  P50="$(sed -n "${P50_INDEX}p" "$TMP_TIMES")"
  P95="$(sed -n "${P95_INDEX}p" "$TMP_TIMES")"

  RPS="$(awk -v success="$SUCCESS" -v duration="$DURATION" 'BEGIN { printf "%.2f", success / duration }')"
else
  AVG="0"
  MIN="0"
  MAX="0"
  P50="0"
  P95="0"
  RPS="0"
fi

{
  echo "Resumo do teste de carga"
  echo "======================="
  echo "Versão: $VERSION_LABEL"
  echo "URL: $URL"
  echo "Requisições totais: $TOTAL"
  echo "Concorrência: $CONCURRENCY"
  echo "Sucessos HTTP 2xx/3xx: $SUCCESS"
  echo "Falhas: $FAILURES"
  echo "Duração total: ${DURATION}s"
  echo "Throughput: ${RPS} req/s"
  echo ""
  echo "Tempo de resposta em segundos"
  echo "Mínimo: $MIN"
  echo "Médio: $AVG"
  echo "P50: $P50"
  echo "P95: $P95"
  echo "Máximo: $MAX"
  echo ""
  echo "Arquivo CSV: $RESULT_FILE"
} | tee "$SUMMARY_FILE"

echo ""
echo "Resumo salvo em: $SUMMARY_FILE"
