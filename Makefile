.RECIPEPREFIX := >

-include .env

MINIKUBE_PROFILE ?= pspd
NAMESPACE ?= pspd
GATEWAY_HOST ?= api.pspd.local
FRONTEND_HOST ?= frontend.pspd.local

export MINIKUBE_PROFILE
export NAMESPACE
export GATEWAY_HOST
export FRONTEND_HOST
export AUTHORIZATION_SERVICE_URL
export ANTIFRAUD_SERVICE_URL
export PAYMENT_GATEWAY_URL
export API_TOKEN
export MOCK_CARD_KEY

.PHONY: help start ingress host namespace app-secret ghcr-secret secret deploy status metrics hpa load-test test-internal test-external test-config test-network clean restart

help:
> @echo "Comandos disponíveis:"
> @echo "  make start          - Inicia o Minikube no perfil PSPD com Calico"
> @echo "  make ingress        - Habilita o NGINX Ingress Controller"
> @echo "  make host           - Configura/atualiza o host local do Ingress"
> @echo "  make namespace      - Cria/atualiza o namespace PSPD"
> @echo "  make secret         - Cria/atualiza Secrets a partir do .env"
> @echo "  make deploy         - Aplica manifests com Kustomize e cria Secret"
> @echo "  make status         - Mostra recursos do namespace PSPD"
> @echo "  make metrics        - Habilita metrics-server para uso do HPA"
> @echo "  make hpa            - Mostra o HPA do payment-gateway"
> @echo "  make load-test      - Executa teste de carga no payment-gateway via Ingress"
> @echo "  make test-internal  - Testa comunicação interna autorizada via payment-gateway"
> @echo "  make test-external  - Testa acesso externo via Ingress"
> @echo "  make test-config    - Testa ConfigMap e Secret"
> @echo "  make test-network   - Testa NetworkPolicies"
> @echo "  make clean          - Remove recursos criados pelo Kustomize"
> @echo "  make restart        - Executa start + ingress + host + deploy + metrics + status"

start:
> minikube start -p $(MINIKUBE_PROFILE) --driver=docker --cni=calico
> kubectl config use-context $(MINIKUBE_PROFILE)

ingress:
> minikube -p $(MINIKUBE_PROFILE) addons enable ingress
> kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=180s

host:
> @IP=$$(minikube -p $(MINIKUBE_PROFILE) ip); \
> for HOST in $(GATEWAY_HOST) $(FRONTEND_HOST); do \
>   if grep -q "$$HOST" /etc/hosts; then \
>     sudo sed -i "/$$HOST/d" /etc/hosts; \
>   fi; \
>   echo "$$IP $$HOST" | sudo tee -a /etc/hosts > /dev/null; \
>   echo "$$HOST configurado para $$IP"; \
> done

namespace:
> kubectl apply -f manifests/workloads/00-namespace.yaml

app-secret: namespace
> ./scripts/create-secret.sh

ghcr-secret: namespace
> ./scripts/create-ghcr-secret.sh

secret: app-secret ghcr-secret

deploy: namespace secret
> kubectl apply -k .
> kubectl rollout status deployment/payment-gateway -n $(NAMESPACE) --timeout=120s
> kubectl rollout status deployment/authorization-service -n $(NAMESPACE) --timeout=120s
> kubectl rollout status deployment/antifraud-service -n $(NAMESPACE) --timeout=120s
> kubectl rollout status deployment/frontend -n $(NAMESPACE) --timeout=120s

status:
> kubectl get all -n $(NAMESPACE)
> kubectl get ingress -n $(NAMESPACE)
> kubectl get configmap -n $(NAMESPACE)
> kubectl get secret -n $(NAMESPACE)
> kubectl get networkpolicy -n $(NAMESPACE)
> kubectl get hpa -n $(NAMESPACE)

metrics:
> minikube -p $(MINIKUBE_PROFILE) addons enable metrics-server
> kubectl wait --for=condition=available deployment/metrics-server -n kube-system --timeout=180s
> sleep 20
> kubectl top pods -n $(NAMESPACE)

hpa:
> kubectl get hpa -n $(NAMESPACE)
> kubectl describe hpa payment-gateway-hpa -n $(NAMESPACE)

load-test:
> ./scripts/load-test.sh

test-internal:
> ./scripts/test-internal.sh

test-external:
> ./scripts/test-external.sh

test-config:
> ./scripts/test-config.sh

test-network:
> ./scripts/test-network-policy.sh

clean:
> kubectl delete secret app-secret -n $(NAMESPACE) --ignore-not-found || true
> kubectl delete secret ghcr-secret -n $(NAMESPACE) --ignore-not-found || true
> kubectl delete -k . --ignore-not-found || true

restart: start ingress host deploy metrics status
