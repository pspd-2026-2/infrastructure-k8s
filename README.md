# Infraestrutura Kubernetes — Sistema de Análise de Risco Financeiro

Este diretório contém a infraestrutura Kubernetes do projeto de microserviços para análise de risco financeiro. A entrega cobre a implantação, exposição, configuração, proteção, escalabilidade e validação dos componentes da aplicação em um cluster local com Minikube.

A infraestrutura foi organizada para simular um ambiente próximo de produção, mantendo compatibilidade com execução local. Para isso, utiliza Kubernetes, Kustomize, NGINX Ingress Controller, Calico, ConfigMap, Secret, NetworkPolicies, Horizontal Pod Autoscaler e scripts operacionais via Makefile.

## Sumário

- [Visão geral da arquitetura](#visão-geral-da-arquitetura)
- [Componentes implantados](#componentes-implantados)
- [Estrutura do diretório](#estrutura-do-diretório)
- [Pré-requisitos](#pré-requisitos)
- [Variáveis de ambiente e segredos](#variáveis-de-ambiente-e-segredos)
- [Configuração não sensível com ConfigMap](#configuração-não-sensível-com-configmap)
- [Imagens privadas no GHCR](#imagens-privadas-no-ghcr)
- [Portas e comunicação interna](#portas-e-comunicação-interna)
- [Ingress](#ingress)
- [Requests, limits e perfil de recursos](#requests-limits-e-perfil-de-recursos)
- [Readiness e liveness probes](#readiness-e-liveness-probes)
- [NetworkPolicies](#networkpolicies)
- [Horizontal Pod Autoscaler](#horizontal-pod-autoscaler)
- [Makefile](#makefile)
- [Fluxo recomendado de execução](#fluxo-recomendado-de-execução)
- [Testes de validação](#testes-de-validação)
- [Troubleshooting](#troubleshooting)
- [Estado atual da entrega](#estado-atual-da-entrega)

## Visão geral da arquitetura

A aplicação é composta por quatro componentes principais:

- `frontend`: interface web da aplicação.
- `payment-gateway`: API Gateway e ponto central de entrada das chamadas de negócio.
- `authorization-service`: serviço interno de autorização de pagamentos.
- `antifraud-service`: serviço interno de análise antifraude.

O fluxo lógico da aplicação é:

```text
Cliente externo
    |
    v
Ingress NGINX
    |
    |-- frontend.pspd.local
    |       |
    |       v
    |     payment-gateway
    |
    |-- api.pspd.local
            |
            v
      payment-gateway
            |
            |-- authorization-service
            |
            |-- antifraud-service
```

O `frontend` e o `payment-gateway` são expostos externamente apenas via Ingress. Os serviços internos `authorization-service` e `antifraud-service` permanecem como `ClusterIP`, acessíveis somente dentro do cluster e conforme permitido pelas NetworkPolicies.

## Componentes implantados

| Componente | Função | Imagem | Tipo de Service | Exposição externa |
|---|---|---|---|---|
| `frontend` | Interface web | `ghcr.io/pspd-2026-2/frontend:latest` | `ClusterIP` | `frontend.pspd.local` |
| `payment-gateway` | API Gateway | `ghcr.io/pspd-2026-2/gateway:latest` | `ClusterIP` | `api.pspd.local` |
| `authorization-service` | Serviço A — Autorizador | `ghcr.io/pspd-2026-2/service-a-authorizer:latest` | `ClusterIP` | Não |
| `antifraud-service` | Serviço B — Antifraude | `ghcr.io/pspd-2026-2/service-b-antifraud:latest` | `ClusterIP` | Não |

Todas as aplicações principais já utilizam imagens reais publicadas no GitHub Container Registry. As imagens privadas são consumidas pelo Kubernetes por meio do `imagePullSecret` chamado `ghcr-secret`.

## Estrutura do diretório

```text
.
├── .env.example
├── .gitignore
├── kustomization.yaml
├── Makefile
├── manifests
│   ├── configs
│   │   ├── app-config.yaml
│   │   └── payment-gateway-hpa.yaml
│   ├── networking
│   │   ├── 00-default-deny-ingress.yaml
│   │   ├── 10-allow-ingress-to-payment-gateway.yaml
│   │   ├── 11-allow-ingress-to-frontend.yaml
│   │   ├── 20-allow-payment-gateway-to-internal-services.yaml
│   │   ├── 30-allow-frontend-to-payment-gateway.yaml
│   │   ├── frontend-ingress.yaml
│   │   └── payment-gateway-ingress.yaml
│   └── workloads
│       ├── 00-namespace.yaml
│       ├── antifraud-service.yaml
│       ├── authorization-service.yaml
│       ├── frontend.yaml
│       └── payment-gateway.yaml
├── scripts
│   ├── check-grpc.sh
│   ├── create-ghcr-secret.sh
│   ├── create-secret.sh
│   ├── load-test.sh
│   ├── test-config.sh
│   ├── test-external.sh
│   ├── test-internal.sh
│   └── test-network-policy.sh
├── tests
│   └── config-test-pod.yaml
└── README.md
```

### `manifests/workloads`

Contém os Deployments e Services da aplicação. Cada componente possui um arquivo próprio, facilitando manutenção, revisão e substituição de imagens.

### `manifests/networking`

Contém os Ingresses e as NetworkPolicies. Essa separação deixa claro quais recursos expõem a aplicação e quais controlam o tráfego interno.

### `manifests/configs`

Contém o `ConfigMap` da aplicação e o `HorizontalPodAutoscaler` do `payment-gateway`.

### `scripts`

Contém scripts de criação de Secrets, validação funcional, teste de rede, teste de configuração, teste gRPC e carga.

### `tests`

Contém manifests auxiliares usados exclusivamente para validação, como o pod temporário `config-test`.

## Pré-requisitos

Para executar localmente:

- Docker.
- Minikube.
- kubectl.
- Make.
- curl.
- Permissão para editar `/etc/hosts`.
- Ambiente Linux ou compatível com shell POSIX.
- Token do GitHub com acesso de leitura aos packages privados do GHCR.

O cluster local é criado com Calico:

```bash
minikube start -p pspd --driver=docker --cni=calico
```

O Calico é necessário para que as NetworkPolicies sejam efetivamente aplicadas. Sem um CNI compatível, os manifests de NetworkPolicy podem ser aceitos pelo cluster, mas o bloqueio de tráfego pode não ocorrer.

## Variáveis de ambiente e segredos

O arquivo `.env` deve ser criado localmente a partir do `.env.example`:

```bash
cp .env.example .env
```

Esse arquivo não deve ser versionado.

Exemplo de variáveis esperadas:

```env
NAMESPACE=pspd
MINIKUBE_PROFILE=pspd
GATEWAY_HOST=api.pspd.local
FRONTEND_HOST=frontend.pspd.local

API_TOKEN=pspd-local-dev-token
MOCK_CARD_KEY=pspd-local-mock-card-key

GHCR_SERVER=ghcr.io
GHCR_SECRET_NAME=ghcr-secret
GHCR_USERNAME=seu-usuario-github
GHCR_TOKEN=seu-token-com-read-packages
GHCR_EMAIL=seu-email

AUTHORIZATION_SERVICE_URL=http://authorization-service:8001
ANTIFRAUD_SERVICE_URL=http://antifraud-service:8002
PAYMENT_GATEWAY_URL=http://payment-gateway:8000
FRONTEND_URL=http://frontend:80
```

### `app-secret`

O Secret `app-secret` armazena dados sensíveis simulados da aplicação:

- `API_TOKEN`
- `MOCK_CARD_KEY`

Ele é criado dinamicamente pelo script:

```bash
./scripts/create-secret.sh
```

Esses valores demonstram o uso correto de Secret para dados sensíveis, evitando que tokens e chaves sejam fixados diretamente nos manifests.

### `ghcr-secret`

O Secret `ghcr-secret` permite que o Kubernetes faça pull das imagens privadas no GHCR:

```bash
./scripts/create-ghcr-secret.sh
```

O token precisa ter permissão de leitura nos packages privados usados no projeto.

## Configuração não sensível com ConfigMap

O ConfigMap `app-config` centraliza as configurações não sensíveis da aplicação:

```yaml
AUTHORIZATION_SERVICE_URL: "http://authorization-service:8001"
ANTIFRAUD_SERVICE_URL: "http://antifraud-service:8002"
PAYMENT_GATEWAY_PORT: "8000"
DEFAULT_PROTOCOL: "rest"
ANTIFRAUD_REST_URL: "http://antifraud-service:8002"
AUTHORIZER_REST_URL: "http://authorization-service:8001"
ANTIFRAUD_GRPC_ADDR: "antifraud-service:50051"
AUTHORIZER_GRPC_ADDR: "authorization-service:50052"
GRPC_TIMEOUT: "5.0"
REST_TIMEOUT: "5.0"
LOG_LEVEL: "INFO"
```

O `payment-gateway` consome esse ConfigMap via `envFrom`, permitindo alterar endpoints, protocolo padrão, timeouts e nível de log sem reconstruir a imagem da aplicação.

## Imagens privadas no GHCR

As imagens reais utilizadas são:

```text
ghcr.io/pspd-2026-2/frontend:latest
ghcr.io/pspd-2026-2/gateway:latest
ghcr.io/pspd-2026-2/service-a-authorizer:latest
ghcr.io/pspd-2026-2/service-b-antifraud:latest
```

Todos os Deployments que usam imagens privadas possuem:

```yaml
imagePullSecrets:
  - name: ghcr-secret
```

Para testar o acesso local ao registry:

```bash
set -a
source .env
set +a

docker logout ghcr.io

echo "$GHCR_TOKEN" | docker login ghcr.io \
  -u "$GHCR_USERNAME" \
  --password-stdin

docker pull ghcr.io/pspd-2026-2/gateway:latest
docker pull ghcr.io/pspd-2026-2/service-a-authorizer:latest
docker pull ghcr.io/pspd-2026-2/service-b-antifraud:latest
docker pull ghcr.io/pspd-2026-2/frontend:latest
```

Para uma entrega mais rastreável, o ideal em produção seria trocar `latest` por tags imutáveis, como hash de commit ou versão de release.

## Portas e comunicação interna

| Componente | Porta do Service | Porta real do container | Observação |
|---|---:|---:|---|
| `frontend` | 80 | 80 | Acessado externamente por `frontend.pspd.local` |
| `payment-gateway` | 8000 | 8000 | Acessado por Ingress e pelo frontend |
| `authorization-service` HTTP | 8001 | 8081 | Service mantém contrato interno em 8001 e encaminha para 8081 |
| `authorization-service` gRPC | 50052 | 50052 | Disponível internamente |
| `antifraud-service` HTTP | 8002 | 8002 | Disponível internamente |
| `antifraud-service` gRPC | 50051 | 50051 | Disponível internamente |

A decisão de manter o `authorization-service` exposto internamente na porta `8001`, mesmo com container escutando em `8081`, preserva o contrato interno usado pelo gateway:

```text
http://authorization-service:8001
```

O Service realiza o mapeamento:

```yaml
port: 8001
targetPort: 8081
```

## Ingress

O NGINX Ingress Controller é usado para expor os pontos de entrada HTTP.

Hosts locais:

```text
api.pspd.local
frontend.pspd.local
```

Rotas:

| Host | Backend |
|---|---|
| `api.pspd.local` | `payment-gateway:8000` |
| `frontend.pspd.local` | `frontend:80` |

Os Services continuam como `ClusterIP`. Não há exposição direta via NodePort ou LoadBalancer para os workloads da aplicação.

A configuração de `/etc/hosts` é automatizada por:

```bash
make host
```

## Requests, limits e perfil de recursos

Os manifests atuais usam um perfil leve adequado ao Minikube. Para um perfil mais próximo de produção, mas ainda seguro para ambiente local, recomenda-se o seguinte ajuste:

| Componente | Requests CPU | Requests Memória | Limits CPU | Limits Memória | Justificativa |
|---|---:|---:|---:|---:|---|
| `frontend` | `100m` | `128Mi` | `500m` | `256Mi` | Servidor web leve, mas com margem para servir assets |
| `payment-gateway` | `250m` | `256Mi` | `1000m` | `512Mi` | Ponto central de entrada, sujeito a maior carga |
| `authorization-service` | `100m` | `128Mi` | `500m` | `256Mi` | Serviço interno com 2 réplicas e processamento moderado |
| `antifraud-service` | `100m` | `128Mi` | `500m` | `256Mi` | Serviço interno com 2 réplicas e endpoints REST/gRPC |
| Pods de teste | `50m` | `64Mi` | `100m` | `128Mi` | Execução curta e controlada |

Esse perfil é mais robusto que o inicial, sem exagerar para Minikube. Para produção real, os valores devem ser recalibrados com base em métricas de uso, testes de carga e comportamento das aplicações reais.

### Blocos sugeridos de resources

`frontend`:

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"
```

`payment-gateway`:

```yaml
resources:
  requests:
    cpu: "250m"
    memory: "256Mi"
  limits:
    cpu: "1000m"
    memory: "512Mi"
```

`authorization-service` e `antifraud-service`:

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"
```

## Readiness e liveness probes

Todos os Deployments possuem probes configuradas.

| Componente | Readiness | Liveness | Observação |
|---|---|---|---|
| `frontend` | HTTP `/` na porta 80 | HTTP `/` na porta 80 | Valida servidor web |
| `payment-gateway` | HTTP `/healthz` na porta 8000 | HTTP `/healthz` na porta 8000 | Valida endpoint de saúde da API |
| `authorization-service` | TCP socket na porta 8081 | TCP socket na porta 8081 | Evita falhas por ausência de rota HTTP `/` |
| `antifraud-service` | TCP socket na porta 8002 | TCP socket na porta 8002 | Valida abertura da porta REST |

O uso de `tcpSocket` no `authorization-service` e no `antifraud-service` foi adotado porque os serviços reais podem não possuir endpoint HTTP de saúde padronizado. Assim, o Kubernetes valida se a aplicação está escutando na porta correta, sem depender de uma rota específica.

## Réplicas

Os serviços internos foram configurados com duas réplicas:

```text
authorization-service: 2
antifraud-service: 2
```

Essa escolha aumenta a disponibilidade dos serviços internos. Caso uma instância falhe, a outra continua atendendo enquanto o Kubernetes recria o pod indisponível.

O `payment-gateway` começa com uma réplica e é controlado pelo HPA. O `frontend` permanece com uma réplica no ambiente local, suficiente para a validação da disciplina.

## NetworkPolicies

As NetworkPolicies aplicam o princípio de menor privilégio dentro do namespace `pspd`.

Políticas configuradas:

```text
default-deny-ingress
allow-ingress-to-payment-gateway
allow-ingress-to-frontend
allow-frontend-to-payment-gateway
allow-payment-gateway-to-authorization-service
allow-payment-gateway-to-antifraud-service
```

Fluxos permitidos:

```text
ingress-nginx -> frontend:80
ingress-nginx -> payment-gateway:8000
frontend -> payment-gateway:8000
payment-gateway -> authorization-service:8001
payment-gateway -> antifraud-service:8002
payment-gateway -> antifraud-service:50051
```

Fluxos bloqueados:

```text
pod genérico -> frontend
pod genérico -> payment-gateway
pod genérico -> authorization-service
pod genérico -> antifraud-service
authorization-service -> antifraud-service
antifraud-service -> authorization-service
frontend -> authorization-service
frontend -> antifraud-service
```

Observação importante: as políticas configuradas controlam tráfego de entrada (`Ingress`) nos pods. O tráfego de saída (`Egress`) não foi bloqueado explicitamente, o que é aceitável para esta etapa acadêmica. Em produção, recomenda-se complementar com políticas de egress.

## Horizontal Pod Autoscaler

O HPA foi configurado para o `payment-gateway`:

```yaml
minReplicas: 1
maxReplicas: 4
averageUtilization: 70
```

O HPA usa métricas de CPU. Por isso, os `requests.cpu` do `payment-gateway` são obrigatórios e já estão definidos.

Para habilitar métricas no Minikube:

```bash
make metrics
```

Para consultar o HPA:

```bash
make hpa
```

Em baixa carga, o gateway tende a permanecer com uma réplica. Sob carga, pode escalar até quatro réplicas.

## Makefile

O Makefile centraliza a operação da infraestrutura.

Comandos disponíveis:

```text
make start          - Inicia o Minikube no perfil PSPD com Calico
make ingress        - Habilita o NGINX Ingress Controller
make host           - Configura os hosts locais do Ingress
make namespace      - Cria/atualiza o namespace PSPD
make secret         - Cria/atualiza app-secret e ghcr-secret
make deploy         - Aplica manifests com Kustomize e aguarda rollouts
make status         - Mostra recursos do namespace PSPD
make metrics        - Habilita metrics-server para uso do HPA
make hpa            - Mostra o HPA do payment-gateway
make load-test      - Executa teste de carga no payment-gateway via Ingress
make test-internal  - Testa comunicação interna autorizada
make test-external  - Testa acesso externo via Ingress
make test-config    - Testa ConfigMap e Secret
make test-network   - Testa NetworkPolicies
make clean          - Remove recursos criados pelo Kustomize
make restart        - Executa start + ingress + host + deploy + metrics + status
```

## Fluxo recomendado de execução

### 1. Preparar `.env`

```bash
cp .env.example .env
```

Edite o `.env` com os valores locais e credenciais do GHCR.

### 2. Subir cluster

```bash
make start
make ingress
make host
```

### 3. Aplicar infraestrutura

```bash
make deploy
```

### 4. Verificar estado

```bash
make status
```

Resultado esperado:

```text
frontend               Running
payment-gateway        Running
authorization-service  Running
antifraud-service      Running
```

### 5. Validar ambiente

```bash
make test-config
make test-internal
make test-external
make test-network
```

### 6. Validar HPA e carga

```bash
make metrics
make hpa
make load-test
```

## Testes de validação

### Teste de configuração

Executado por:

```bash
make test-config
```

Esse teste cria um pod temporário `config-test`, injeta o `ConfigMap` e o `Secret` com `envFrom`, imprime as variáveis esperadas e remove o pod ao final.

Valida:

```text
AUTHORIZATION_SERVICE_URL
ANTIFRAUD_SERVICE_URL
PAYMENT_GATEWAY_PORT
LOG_LEVEL
API_TOKEN
MOCK_CARD_KEY
```

### Teste interno

Executado por:

```bash
make test-internal
```

Cria um pod temporário com label `app=payment-gateway`, simulando o gateway. Esse detalhe é importante porque as NetworkPolicies só permitem que pods com essa label acessem os serviços internos.

Valida:

```text
payment-gateway -> authorization-service
payment-gateway -> antifraud-service
```

### Teste externo

Executado por:

```bash
make test-external
```

Valida:

```text
http://api.pspd.local/healthz
http://frontend.pspd.local
```

### Teste de NetworkPolicy

Executado por:

```bash
make test-network
```

Valida tanto os acessos permitidos quanto os bloqueios esperados:

- Ingress consegue acessar `frontend`.
- Ingress consegue acessar `payment-gateway`.
- Pod genérico não acessa os serviços protegidos.
- Pod com label `app=frontend` acessa o gateway.
- Pod com label `app=payment-gateway` acessa serviços internos.

### Teste gRPC

Executado por:

```bash
./scripts/check-grpc.sh
```

Cria um pod com `grpcurl` para validar exposição de serviços gRPC internos.

### Teste de carga

Executado por:

```bash
make load-test
```

O script gera arquivos CSV e resumo textual com métricas:

- Total de requisições.
- Concorrência.
- Sucessos.
- Falhas.
- Duração.
- Throughput.
- Latência mínima, média, P50, P95 e máxima.

Os resultados são salvos em:

```text
docs/performance/
```

## Troubleshooting

### `ImagePullBackOff`, `denied` ou `unauthorized`

Causa provável: problema no token do GHCR, package privado ou `imagePullSecret`.

Checklist:

```bash
set -a
source .env
set +a

docker logout ghcr.io

echo "$GHCR_TOKEN" | docker login ghcr.io \
  -u "$GHCR_USERNAME" \
  --password-stdin

docker pull ghcr.io/pspd-2026-2/gateway:latest
```

Se o pull local funcionar, recrie o secret:

```bash
./scripts/create-ghcr-secret.sh
```

Depois reinicie o Deployment afetado:

```bash
kubectl rollout restart deployment/<nome-do-deployment> -n pspd
```

### Pod reiniciando por falha de probe

Verifique eventos e logs:

```bash
kubectl describe pod <pod> -n pspd
kubectl logs <pod> -n pspd --previous
```

Causas comuns:

- Porta do container diferente da porta do Service.
- Endpoint de health check inexistente.
- Aplicação escutando em porta diferente da configurada.
- Probe HTTP apontando para uma rota que não retorna 200.

No caso do `authorization-service`, a aplicação real escuta HTTP em `8081`, enquanto o Service interno expõe `8001`.

### `make test-config` falhando com pod `Completed`

O pod de teste precisa permanecer ativo tempo suficiente para capturar logs. O manifesto `tests/config-test-pod.yaml` mantém o container vivo com:

```sh
sleep 300
```

O script deve usar `kubectl logs` para ler a saída e remover o pod ao final.

### NetworkPolicy não bloqueia tráfego

Confirme que o cluster foi iniciado com Calico:

```bash
minikube start -p pspd --driver=docker --cni=calico
```

Sem CNI compatível, as NetworkPolicies podem ser criadas, mas não aplicadas de fato.

### HPA não mostra métricas

Habilite o metrics-server:

```bash
make metrics
```

Depois verifique:

```bash
kubectl top pods -n pspd
kubectl get hpa -n pspd
```

## Observações para produção

O ambiente atual é local e acadêmico, mas já aplica práticas importantes:

- Separação de responsabilidades por componente.
- Services internos estáveis.
- Exposição controlada por Ingress.
- Uso de ConfigMap para configuração não sensível.
- Uso de Secret para credenciais e tokens.
- Uso de `imagePullSecrets` para imagens privadas.
- Probes de saúde.
- Requests e limits.
- HPA.
- NetworkPolicies com default deny.
- Scripts reprodutíveis de operação e teste.

Para uma produção real, recomenda-se evoluir os seguintes pontos:

- Usar tags imutáveis em vez de `latest`.
- Adicionar TLS nos Ingresses.
- Usar External Secrets, Sealed Secrets ou integração com cofre de segredos.
- Adicionar políticas de egress.
- Implementar endpoints `/healthz` padronizados em todos os microserviços.
- Adicionar PodDisruptionBudget.
- Adicionar observabilidade com métricas, logs e tracing.
- Separar ambientes `dev`, `staging` e `prod`.
- Configurar limites com base em métricas reais de carga.
- Automatizar deploy via CI/CD.

## Estado atual da entrega

A infraestrutura atual contempla:

- Cluster local com Minikube.
- CNI Calico.
- Namespace dedicado `pspd`.
- Frontend real implantado.
- Payment Gateway real implantado.
- Authorization Service real implantado.
- Antifraud Service real implantado.
- Imagens privadas do GHCR com `imagePullSecrets`.
- Services internos `ClusterIP`.
- Ingress para frontend e gateway.
- ConfigMap para configuração não sensível.
- Secret dinâmico para dados sensíveis.
- Secret para autenticação no GHCR.
- Probes de readiness e liveness.
- Réplicas estáticas nos serviços internos.
- HPA no gateway.
- NetworkPolicies restritivas.
- Scripts de teste funcional, configuração, segurança, gRPC e carga.
- Organização com Kustomize.
- Operação automatizada com Makefile.

Com isso, a infraestrutura da Pessoa 4 entrega uma base Kubernetes funcional, segura e reprodutível para executar os microserviços do sistema de análise de risco financeiro em ambiente local, com práticas compatíveis com um desenho profissional de implantação.
