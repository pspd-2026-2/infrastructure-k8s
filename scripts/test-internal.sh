#!/bin/sh
set -eu

NS="${NAMESPACE:-pspd}"
POD="curl-test"

echo "Testando comunicação interna autorizada:"
echo "payment-gateway -> authorization-service"
echo "payment-gateway -> antifraud-service"
echo ""

kubectl delete pod "$POD" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true

cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: $POD
  namespace: $NS
  labels:
    app: payment-gateway
spec:
  restartPolicy: Never
  containers:
    - name: $POD
      image: curlimages/curl:8.10.1
      resources:
        requests:
          cpu: 50m
          memory: 64Mi
        limits:
          cpu: 100m
          memory: 128Mi
      command:
        - sh
        - -c
        - |
          echo 'authorization-service:'
          curl -fsS --connect-timeout 3 --max-time 5 http://authorization-service:8001
          echo ''
          echo 'antifraud-service:'
          curl -sS --connect-timeout 3 --max-time 5 http://antifraud-service:8002
          echo ''
EOF

for _ in $(seq 1 30); do
  PHASE="$(kubectl get pod "$POD" -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || echo Pending)"

  if [ "$PHASE" = "Succeeded" ] || [ "$PHASE" = "Failed" ]; then
    break
  fi

  sleep 1
done

kubectl logs "$POD" -n "$NS" || true

PHASE="$(kubectl get pod "$POD" -n "$NS" -o jsonpath='{.status.phase}')"

kubectl delete pod "$POD" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true

if [ "$PHASE" != "Succeeded" ]; then
  echo "ERRO: teste interno falhou. Phase=$PHASE"
  exit 1
fi

echo ""
echo "OK: comunicação interna autorizada funcionando"
