-include .env

MINIKUBE_PROFILE ?= pspd
NAMESPACE ?= pspd
GATEWAY_HOST ?= api.pspd.local
FRONTEND_HOST ?= frontend.pspd.local

ARCH := $(shell uname -m)
ifeq ($(ARCH),arm64)
  PLATFORM ?= linux/arm64
else ifeq ($(ARCH),aarch64)
  PLATFORM ?= linux/arm64
else
  PLATFORM ?= linux/amd64
endif
IMAGE_PREFIX ?= ghcr.io/pspd-2026-2
INGRESS_PF_LOG ?= /tmp/pspd-ingress-portforward.log

export MINIKUBE_PROFILE
export NAMESPACE
export GATEWAY_HOST
export FRONTEND_HOST
export AUTHORIZATION_SERVICE_URL
export ANTIFRAUD_SERVICE_URL
export PAYMENT_GATEWAY_URL
export API_TOKEN
export MOCK_CARD_KEY

.PHONY: help start ingress host unhost namespace app-secret ghcr-secret secret deploy status metrics hpa load-test test-internal test-external test-config test-network clean restart build-images deploy-local local port-forward ingress-forward stop-forward up down py-setup test-python

help:
	@echo "Comandos principais (Mac/arm64, driver docker):"
	@echo "  make up             - Sobe TUDO: cluster + ingress + hosts + deploy + port-forward :80"
	@echo "  make down           - Limpa TUDO: para port-forward + remove hosts + deleta o cluster"
	@echo ""
	@echo "Comandos disponíveis:"
	@echo "  make start          - Inicia o Minikube no perfil PSPD com Calico"
	@echo "  make ingress        - Habilita o NGINX Ingress Controller"
	@echo "  make host           - Configura/atualiza o host local do Ingress"
	@echo "  make namespace      - Cria/atualiza o namespace PSPD"
	@echo "  make secret         - Cria/atualiza Secrets a partir do .env"
	@echo "  make deploy         - Aplica manifests com Kustomize e cria Secret (GHCR/amd64)"
	@echo "  make status         - Mostra recursos do namespace PSPD"
	@echo "  make metrics        - Habilita metrics-server para uso do HPA"
	@echo "  make hpa            - Mostra o HPA do payment-gateway"
	@echo "  make load-test      - Executa teste de carga no payment-gateway via Ingress"
	@echo "  make test-internal  - Testa comunicação interna autorizada via payment-gateway"
	@echo "  make test-external  - Testa acesso externo via Ingress"
	@echo "  make test-config    - Testa ConfigMap e Secret"
	@echo "  make test-network   - Testa NetworkPolicies"
	@echo "  make clean          - Remove recursos criados pelo Kustomize"
	@echo "  make restart        - Executa start + ingress + host + deploy + metrics + status"
	@echo ""
	@echo "Comandos para Mac/arm64 (build local, sem GHCR):"
	@echo "  make local          - Sobe tudo no Mac: start+ingress+host+build+deploy+metrics"
	@echo "  make build-images   - Builda as 4 imagens nativas ($(PLATFORM)) no minikube"
	@echo "  make deploy-local   - Deploy usando imagens locais (overlay/local)"
	@echo "  make port-forward   - Expõe o gateway em localhost:8000"
	@echo "  make py-setup       - Cria venv Python com deps do gateway"
	@echo "  make test-python    - Roda pytest (requer port-forward ativo)"

start:
	minikube start -p $(MINIKUBE_PROFILE) --driver=docker --cni=calico
	kubectl config use-context $(MINIKUBE_PROFILE)

ingress:
	minikube -p $(MINIKUBE_PROFILE) addons enable ingress
	kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=180s

host:
	@DRIVER=$$(minikube -p $(MINIKUBE_PROFILE) profile list -o json 2>/dev/null | python3 -c "import sys,json; profiles=json.load(sys.stdin).get('valid',[]); p=[x for x in profiles if x['Name']=='$(MINIKUBE_PROFILE)']; print(p[0]['Config']['Driver'] if p else 'docker')" 2>/dev/null || echo docker); \
	if [ "$$DRIVER" = "docker" ]; then IP=127.0.0.1; else IP=$$(minikube -p $(MINIKUBE_PROFILE) ip); fi; \
	for HOST in $(GATEWAY_HOST) $(FRONTEND_HOST); do \
	  if grep -q "$$HOST" /etc/hosts; then \
	    sudo sed -i "" "/$$HOST/d" /etc/hosts; \
	  fi; \
	  echo "$$IP $$HOST" | sudo tee -a /etc/hosts > /dev/null; \
	  echo "$$HOST configurado para $$IP"; \
	done

unhost:
	@for HOST in $(GATEWAY_HOST) $(FRONTEND_HOST); do \
	  if grep -q "$$HOST" /etc/hosts; then \
	    sudo sed -i "" "/$$HOST/d" /etc/hosts; \
	    echo "$$HOST removido de /etc/hosts"; \
	  fi; \
	done

namespace:
	kubectl apply -f manifests/workloads/00-namespace.yaml

app-secret: namespace
	./scripts/create-secret.sh

ghcr-secret: namespace
	./scripts/create-ghcr-secret.sh

secret: app-secret ghcr-secret

deploy: namespace secret
	kubectl apply -k .
	kubectl rollout status deployment/payment-gateway -n $(NAMESPACE) --timeout=120s
	kubectl rollout status deployment/authorization-service -n $(NAMESPACE) --timeout=120s
	kubectl rollout status deployment/antifraud-service -n $(NAMESPACE) --timeout=120s
	kubectl rollout status deployment/frontend -n $(NAMESPACE) --timeout=120s

status:
	kubectl get all -n $(NAMESPACE)
	kubectl get ingress -n $(NAMESPACE)
	kubectl get configmap -n $(NAMESPACE)
	kubectl get secret -n $(NAMESPACE)
	kubectl get networkpolicy -n $(NAMESPACE)
	kubectl get hpa -n $(NAMESPACE)

metrics:
	minikube -p $(MINIKUBE_PROFILE) addons enable metrics-server
	kubectl wait --for=condition=available deployment/metrics-server -n kube-system --timeout=180s
	sleep 20
	kubectl top pods -n $(NAMESPACE)

hpa:
	kubectl get hpa -n $(NAMESPACE)
	kubectl describe hpa payment-gateway-hpa -n $(NAMESPACE)

load-test:
	./scripts/load-test.sh

test-internal:
	./scripts/test-internal.sh

test-external:
	./scripts/test-external.sh

test-config:
	./scripts/test-config.sh

test-network:
	./scripts/test-network-policy.sh

clean:
	kubectl delete secret app-secret -n $(NAMESPACE) --ignore-not-found || true
	kubectl delete secret ghcr-secret -n $(NAMESPACE) --ignore-not-found || true
	kubectl delete -k . --ignore-not-found || true

restart: start ingress host deploy metrics status

# ── Targets locais (Mac/arm64, sem GHCR) ─────────────────────────────────────

build-images:
	@echo "Construindo imagens para $(PLATFORM) no docker do minikube..."
	eval $$(minikube -p $(MINIKUBE_PROFILE) docker-env) && \
	docker build --platform $(PLATFORM) -t $(IMAGE_PREFIX)/gateway:local ../gateway && \
	docker build --platform $(PLATFORM) -t $(IMAGE_PREFIX)/service-a-authorizer:local ../service-a-authorizer && \
	docker build --platform $(PLATFORM) -f ../service-b-antifraud/build/Dockerfile -t $(IMAGE_PREFIX)/service-b-antifraud:local ../service-b-antifraud && \
	docker build --platform $(PLATFORM) -t $(IMAGE_PREFIX)/frontend:local ../frontend

deploy-local: namespace app-secret build-images
	kubectl apply -k ../overlays/local
	kubectl rollout status deployment/payment-gateway -n $(NAMESPACE) --timeout=180s
	kubectl rollout status deployment/authorization-service -n $(NAMESPACE) --timeout=180s
	kubectl rollout status deployment/antifraud-service -n $(NAMESPACE) --timeout=180s
	kubectl rollout status deployment/frontend -n $(NAMESPACE) --timeout=180s

local: start ingress host deploy-local metrics status

port-forward:
	kubectl port-forward -n $(NAMESPACE) svc/payment-gateway 8000:8000

# Expõe o Ingress NGINX em 127.0.0.1:80 (necessário no Mac com driver docker,
# onde o IP do minikube não é roteável e o controller é NodePort, não LoadBalancer).
ingress-forward:
	@if pgrep -f "port-forward -n ingress-nginx svc/ingress-nginx-controller" >/dev/null 2>&1; then \
	  echo "port-forward do ingress já está ativo (:80)"; \
	else \
	  echo "Iniciando port-forward do Ingress em 127.0.0.1:80 (requer sudo)..."; \
	  sudo -v; \
	  sudo env KUBECONFIG=$$HOME/.kube/config nohup kubectl port-forward -n ingress-nginx svc/ingress-nginx-controller 80:80 --address 127.0.0.1 > $(INGRESS_PF_LOG) 2>&1 & \
	  sleep 3; \
	  echo "port-forward do Ingress ativo (log: $(INGRESS_PF_LOG))"; \
	fi

stop-forward:
	@sudo pkill -f "port-forward -n ingress-nginx svc/ingress-nginx-controller" 2>/dev/null && echo "port-forward do Ingress parado" || echo "nenhum port-forward do Ingress ativo"

# ── Um comando para tudo / um comando para limpar ────────────────────────────

up: local ingress-forward
	@echo ""
	@echo "Tudo pronto!"
	@echo "  Frontend: http://$(FRONTEND_HOST)"
	@echo "  API:      http://$(GATEWAY_HOST)/healthz"

down: stop-forward unhost
	minikube -p $(MINIKUBE_PROFILE) delete
	@echo "Ambiente removido."

py-setup:
	python3 -m venv ../gateway/.venv
	../gateway/.venv/bin/pip install -r ../gateway/requirements.txt

test-python:
	cd ../gateway && .venv/bin/pytest tests/ -v