#!/bin/sh
set -eu

NS="pspd"
GATEWAY_HOST="${GATEWAY_HOST:-api.pspd.local}"
FRONTEND_HOST="${FRONTEND_HOST:-frontend.pspd.local}"

echo "Testando NetworkPolicies no namespace $NS"
echo ""

echo "1) Testando acesso externo via Ingress ao payment-gateway"
if curl -fsS "http://$GATEWAY_HOST/healthz" | grep -q '"status"'; then
  echo "OK: acesso externo via Ingress permitido ao payment-gateway"
else
  echo "ERRO: acesso externo via Ingress ao payment-gateway falhou"
  exit 1
fi

echo ""
echo "2) Testando acesso externo via Ingress ao frontend"
if curl -fsS "http://$FRONTEND_HOST" >/dev/null; then
  echo "OK: acesso externo via Ingress permitido ao frontend"
else
  echo "ERRO: acesso externo via Ingress ao frontend falhou"
  exit 1
fi

echo ""
echo "3) Testando bloqueio de pod genérico para payment-gateway"
if kubectl run np-blocked-gateway \
  -n "$NS" \
  --rm -i \
  --restart=Never \
  --image=curlimages/curl:8.10.1 \
  --command -- sh -c "curl -fsS --connect-timeout 3 --max-time 5 http://payment-gateway:8000/healthz"; then
  echo "ERRO: pod genérico conseguiu acessar payment-gateway diretamente"
  exit 1
else
  echo "OK: pod genérico bloqueado ao acessar payment-gateway diretamente"
fi

echo ""
echo "4) Testando bloqueio de pod genérico para frontend"
if kubectl run np-blocked-frontend \
  -n "$NS" \
  --rm -i \
  --restart=Never \
  --image=curlimages/curl:8.10.1 \
  --command -- sh -c "curl -fsS --connect-timeout 3 --max-time 5 http://frontend:80"; then
  echo "ERRO: pod genérico conseguiu acessar frontend diretamente"
  exit 1
else
  echo "OK: pod genérico bloqueado ao acessar frontend diretamente"
fi

echo ""
echo "5) Testando bloqueio de pod genérico para authorization-service"
if kubectl run np-blocked-auth \
  -n "$NS" \
  --rm -i \
  --restart=Never \
  --image=curlimages/curl:8.10.1 \
  --command -- sh -c "curl -fsS --connect-timeout 3 --max-time 5 http://authorization-service:8001"; then
  echo "ERRO: pod genérico conseguiu acessar authorization-service"
  exit 1
else
  echo "OK: pod genérico bloqueado ao acessar authorization-service"
fi

echo ""
echo "6) Testando bloqueio de pod genérico para antifraud-service"
if kubectl run np-blocked-antifraud \
  -n "$NS" \
  --rm -i \
  --restart=Never \
  --image=curlimages/curl:8.10.1 \
  --command -- sh -c "curl -fsS --connect-timeout 3 --max-time 5 http://antifraud-service:8002"; then
  echo "ERRO: pod genérico conseguiu acessar antifraud-service"
  exit 1
else
  echo "OK: pod genérico bloqueado ao acessar antifraud-service"
fi

echo ""
echo "7) Simulando frontend acessando payment-gateway"
kubectl run np-frontend-client \
  -n "$NS" \
  --rm -i \
  --restart=Never \
  --image=curlimages/curl:8.10.1 \
  --labels="app=frontend" \
  --command -- sh -c "curl -fsS --connect-timeout 3 --max-time 5 http://gateway:8000/healthz"

echo ""
echo "8) Simulando payment-gateway acessando authorization-service e antifraud-service"
kubectl run np-payment-gateway-client \
  -n "$NS" \
  --rm -i \
  --restart=Never \
  --image=curlimages/curl:8.10.1 \
  --labels="app=payment-gateway" \
  --command -- sh -c "
    echo 'authorization-service:'
    curl -sS --connect-timeout 3 --max-time 5 http://authorization-service:8001
    echo ''
    echo 'antifraud-service:'
    curl -sS --connect-timeout 3 --max-time 5 http://antifraud-service:8002
    echo ''
  "

echo ""
echo "OK: NetworkPolicies funcionando conforme esperado"
