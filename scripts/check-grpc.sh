#!/bin/sh
set -eu

NS="${NAMESPACE:-pspd}"
POD="grpc-test"

echo "Criando pod temporário com grpcurl para listar os serviços gRPC..."

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
      image: fullstorydev/grpcurl:v1.9.1
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
          echo "=== Port 50051 ==="
          /bin/grpcurl -plaintext -max-time 3 antifraud-service:50051 list || echo "failed"
          echo ""
          echo "=== Port 50052 ==="
          /bin/grpcurl -plaintext -max-time 3 antifraud-service:50052 list || echo "failed"
EOF

echo "Aguardando o pod concluir..."
for _ in $(seq 1 30); do
  PHASE="$(kubectl get pod "$POD" -n "$NS" -o jsonpath='{.status.phase}' 2>/dev/null || echo Pending)"
  if [ "$PHASE" = "Succeeded" ] || [ "$PHASE" = "Failed" ]; then
    break
  fi
  sleep 1
done

echo ""
echo "=== RESULTADO DO GRPCURL ==="
kubectl logs "$POD" -n "$NS" || true

kubectl delete pod "$POD" -n "$NS" --ignore-not-found >/dev/null 2>&1 || true
