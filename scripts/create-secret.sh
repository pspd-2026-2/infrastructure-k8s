#!/bin/sh

set -eu

ENV_FILE="${ENV_FILE:-.env}"

case "$ENV_FILE" in
  /*|*/*)
    ENV_PATH="$ENV_FILE"
    ;;
  *)
    ENV_PATH="./$ENV_FILE"
    ;;
esac

if [ ! -f "$ENV_PATH" ]; then
  echo "Arquivo $ENV_PATH não encontrado."
  echo "Crie com: cp .env.example .env"
  exit 1
fi

set -a
# shellcheck disable=SC1090
. "$ENV_PATH"
set +a

NAMESPACE="${NAMESPACE:-pspd}"
API_TOKEN="${API_TOKEN:-}"
MOCK_CARD_KEY="${MOCK_CARD_KEY:-}"

if [ -z "$API_TOKEN" ] || [ -z "$MOCK_CARD_KEY" ]; then
  echo "API_TOKEN e MOCK_CARD_KEY precisam estar definidos no $ENV_PATH"
  exit 1
fi

kubectl create secret generic app-secret \
  -n "$NAMESPACE" \
  --from-literal=API_TOKEN="$API_TOKEN" \
  --from-literal=MOCK_CARD_KEY="$MOCK_CARD_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secret app-secret criado/atualizado no namespace $NAMESPACE"
