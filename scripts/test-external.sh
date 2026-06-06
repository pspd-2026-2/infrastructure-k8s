#!/bin/sh

set -eu

GATEWAY_HOST="${GATEWAY_HOST:-api.pspd.local}"
FRONTEND_HOST="${FRONTEND_HOST:-frontend.pspd.local}"

echo "Testando acesso externo ao Payment Gateway via Ingress:"
curl -fsS "http://$GATEWAY_HOST/healthz"
echo

echo "Testando acesso externo ao Frontend via Ingress:"
curl -fsS "http://$FRONTEND_HOST" >/dev/null
echo "frontend ok"
echo
