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
GHCR_SERVER="${GHCR_SERVER:-ghcr.io}"
GHCR_SECRET_NAME="${GHCR_SECRET_NAME:-ghcr-secret}"

GHCR_USERNAME="${GHCR_USERNAME:-}"
GHCR_TOKEN="${GHCR_TOKEN:-}"
GHCR_EMAIL="${GHCR_EMAIL:-}"
GITHUB_USERNAME="${GITHUB_USERNAME:-}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"
GITHUB_EMAIL="${GITHUB_EMAIL:-}"

if [ -z "$GHCR_USERNAME" ]; then
  GHCR_USERNAME="$GITHUB_USERNAME"
fi

if [ -z "$GHCR_TOKEN" ]; then
  GHCR_TOKEN="$GITHUB_TOKEN"
fi

if [ -z "$GHCR_EMAIL" ]; then
  GHCR_EMAIL="$GITHUB_EMAIL"
fi

if [ -z "$GHCR_EMAIL" ] && [ -n "$GHCR_USERNAME" ]; then
  GHCR_EMAIL="${GHCR_USERNAME}@users.noreply.github.com"
fi

if [ -z "$GHCR_USERNAME" ] || [ -z "$GHCR_TOKEN" ]; then
  echo "GHCR_USERNAME e GHCR_TOKEN precisam estar definidos no $ENV_PATH"
  echo "O token precisa ter permissao de leitura em packages privados do GHCR."
  exit 1
fi

kubectl create secret docker-registry "$GHCR_SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --docker-server="$GHCR_SERVER" \
  --docker-username="$GHCR_USERNAME" \
  --docker-password="$GHCR_TOKEN" \
  --docker-email="$GHCR_EMAIL" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Secret $GHCR_SECRET_NAME criado/atualizado no namespace $NAMESPACE"
