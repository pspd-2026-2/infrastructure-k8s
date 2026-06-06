#!/bin/sh

set -eu

NAMESPACE="${NAMESPACE:-pspd}"
POD_NAME="${POD_NAME:-config-test}"

./scripts/create-secret.sh

kubectl delete pod -n "$NAMESPACE" "$POD_NAME" --ignore-not-found
kubectl apply -f tests/config-test-pod.yaml

sleep 5

kubectl logs -n "$NAMESPACE" "$POD_NAME"
kubectl delete pod -n "$NAMESPACE" "$POD_NAME" --ignore-not-found
