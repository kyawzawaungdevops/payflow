# PayFlow Learning Path

This is the short path through PayFlow. Follow it in order. Use [`docs/README.md`](docs/README.md) when you need the full documentation map.

Optional long-form context: [*Building PayFlow*](https://osomudeya.gumroad.com/l/payflow).

## Day 0: Setup

Install these before Week 1:

| Tool | Why | Check |
|------|-----|-------|
| Docker Desktop / Docker Engine | Runs the services | `docker --version` |
| Git | Clone and update the repo | `git --version` |
| Multipass, macOS only | Required for MicroK8s on Mac | `multipass --version` |
| Editor + terminal | Read files and run commands | Any editor is fine |

Windows users should use WSL2 with Docker Desktop's WSL2 integration. Native PowerShell is not supported for the MicroK8s path.

If a setup command fails, fix it before starting Week 1.

## Overview

| Stage | Focus | Outcome |
|-------|-------|---------|
| Week 1 | Run PayFlow locally on MicroK8s, use the UI, trace a transfer | You understand the product and money path |
| Week 2 | Kubernetes basics, ingress, overlays, network policies, failure drills | You can explain how traffic reaches services and what happens when pods fail |
| Week 3 | Architecture, tracing, monitoring, operations habits | You can whiteboard the system and explain tradeoffs |
| Optional lab | Metrics, logs, and one database sanity check | You can prove whether the system is healthy |
| Week 4 | Cloud infra with EKS or AKS, Terraform, CI/CD | You understand the path from infra to running release |

Shortcut: if MicroK8s is too heavy, start with Docker Compose in Week 1, then return to Kubernetes in Week 2.

## Week 1: Run It And Trace Money

**Goal:** PayFlow runs on your machine, and you can explain what happens when someone sends money.

Do not start with `terraform/`, `./spinup.sh`, deep AWS docs, or every workflow under `.github/workflows/`. Stay on the local path first.

### 1. Deploy With MicroK8s

From the repo root:

```bash
git clone <your-fork-url>
cd payflow-wallet-2

./scripts/deploy-microk8s.sh
bash scripts/setup-hosts-payflow-local.sh

export KUBECONFIG="${HOME}/.kube/microk8s-config"

./scripts/validate.sh --env k8s --host http://api.payflow.local
```

Expected result:

```text
All checks passed - PayFlow is healthy
```

Open `http://www.payflow.local`, register two users, and send money between them.

Read next:

1. [`README.md`](README.md)
2. [`docs/system-flow.md`](docs/system-flow.md)

Checkpoint:

- Which services handle a transfer?
- Which tables change?
- Which queue is used?

### 2. Optional Docker Compose Path

Use this if you want the fastest smoke test or cannot run MicroK8s yet.

```bash
docker compose up -d
./scripts/validate.sh
open http://localhost
```

Tradeoff: Compose teaches the app and money path, but not Kubernetes scheduling, Services, or Ingress.

Gotchas: [`docs/LOCAL-SETUP-GOTCHAS.md`](docs/LOCAL-SETUP-GOTCHAS.md).

### 3. Read The Service Code

For each service, read the `README.md`, then the main server file:

1. [`services/auth-service`](services/auth-service/README.md)
2. [`services/wallet-service`](services/wallet-service/README.md)
3. [`services/transaction-service`](services/transaction-service/README.md)
4. [`services/notification-service`](services/notification-service/README.md)
5. [`services/api-gateway`](services/api-gateway/README.md)
6. [`services/frontend`](services/frontend/README.md)

Pay extra attention to:

- `wallet-service`: balance updates and row locking
- `transaction-service`: transfer orchestration, retries, and circuit breaker behavior

### 4. Understand The Stack Choices

Read [`docs/technology-choices.md`](docs/technology-choices.md).

Pick one tradeoff you can explain clearly, such as:

- PostgreSQL vs document database
- RabbitMQ vs synchronous HTTP
- Redis-backed sessions vs stateless auth

Week 1 is done when you can run the app, validate it, send money, and explain the transfer path without reading from the docs.

## Week 2: Kubernetes Depth

**Goal:** Understand what Kubernetes adds beyond Compose.

Do not run cloud Terraform or `./spinup.sh` yet. Do not apply `k8s/base` directly.

### 1. Traffic And Manifests

Read:

- [`docs/understanding-ingress.md`](docs/understanding-ingress.md)
- [`k8s/overlays/local/README.md`](k8s/overlays/local/README.md)

Key idea: apply an overlay, not raw base manifests.

```bash
kubectl apply -k k8s/overlays/local
```

Why: `k8s/base` is shared YAML. The local overlay adds local images, secrets, quotas, probes, and ingress.

### 2. Isolation

Skim:

- [`k8s/base/policies/network-policies.yaml`](k8s/base/policies/network-policies.yaml)
- One Deployment under `k8s/base/deployments/`

Look for labels, selectors, and which pods are allowed to talk to each other.

### 3. Failure Drills

Use [`docs/HOME-LAB-DRILLS.md`](docs/HOME-LAB-DRILLS.md), or start with this:

```bash
kubectl delete pod -n payflow -l app=transaction-service
kubectl rollout status deployment/transaction-service -n payflow
kubectl get events -n payflow --sort-by='.lastTimestamp' | tail -20
```

Try scaling one service:

```bash
kubectl scale deployment api-gateway -n payflow --replicas=3
```

Checkpoint:

- What does Ingress do?
- What does Service do?
- What does Deployment do?
- What breaks if each one is missing?

### 4. Optional GitOps

Read [`docs/cicd-local.md`](docs/cicd-local.md) and `.github/workflows/gitops-local.yml`.

Goal: understand the path from push, to image build, to manifest update, to Argo CD sync.

Week 2 is done when you can explain Ingress, Service, Deployment, overlays, and one deliberate failure.

## Week 3: Architecture And Operations

**Goal:** Whiteboard PayFlow in about 30 minutes.

Pick a few docs. You do not need to read everything at once.

| Read | Focus |
|------|-------|
| [`docs/architecture.md`](docs/architecture.md) | System design |
| [`docs/ARCHITECTURE-MICROSERVICES-VS-MONOLITH.md`](docs/ARCHITECTURE-MICROSERVICES-VS-MONOLITH.md) | Service boundaries |
| [`docs/tracing-a-single-request.md`](docs/tracing-a-single-request.md) | Request flow |
| [`docs/monitoring.md`](docs/monitoring.md) | Metrics and dashboards |
| [`docs/RUNBOOK.md`](docs/RUNBOOK.md) | Operational checks |
| [`docs/LAB-INCIDENT-STORIES.md`](docs/LAB-INCIDENT-STORIES.md) | Real failure stories |

Patterns to understand:

- Idempotency: safe retries for transaction creation
- Atomic transactions: no half-completed wallet transfer
- Event-driven notification: queue instead of synchronous fan-out
- Circuit breaker: fail fast when a dependency is unhealthy

Week 3 is done when you can draw the request path from browser to notification and defend one major boundary: HTTP, queue, or database.

## Optional Lab: Metrics, Logs, Database

**Goal:** Learn a small operations habit without building a full observability platform.

Use MicroK8s or Compose. The easiest metrics path is:

```bash
docker compose --profile monitoring up -d
```

Then do three things:

1. Pick 2 or 3 health signals, such as latency, error rate, or queue depth.
2. Break one thing, such as RabbitMQ, a pod, or CPU resources.
3. Compare metrics, logs, and one database sanity check.

Helpful docs:

- [`docs/monitoring.md`](docs/monitoring.md)
- [`docs/tracing-a-single-request.md`](docs/tracing-a-single-request.md)
- [`docs/system-flow.md`](docs/system-flow.md)
- [`docs/HOME-LAB-DRILLS.md`](docs/HOME-LAB-DRILLS.md)

This lab is done when you can say which signal moved first, which log explained the cause, and which database check restored confidence.

## Week 4: Cloud, Terraform, CI/CD

**Cost warning:** EKS with managed node groups, RDS, ElastiCache, and Amazon MQ can cost about $8-15 USD per day in `us-east-1`. When finished, run:

```bash
./teardown.sh
```

Do not leave cloud resources running unless you intend to pay for them.

**Goal:** Run the same app on real infrastructure with Terraform, cloud images, Kubernetes deploys, and CI/CD.

### 1. Prepare

You need:

- AWS account and `aws configure`
- `aws sts get-caller-identity` working
- Terraform 1.5 or newer
- `kubectl`
- `helm`

Read first:

- [`docs/README.md`](docs/README.md), AWS EKS infrastructure section
- [`docs/INFRASTRUCTURE-ONBOARDING.md`](docs/INFRASTRUCTURE-ONBOARDING.md), sections 1-2

### 2. EKS Path

Use the scripted order:

```bash
./spinup.sh
# Choose: aws
# Workspace: dev
```

Then follow [`README.md`](README.md), Environment 3: AWS EKS, starting at "After infrastructure".

Image options:

- CI: push to `main`, then use the short SHA from `.github/workflows/build-and-deploy.yml`
- CLI: `./scripts/build-push-ecr.sh <tag>`

Deploy:

```bash
cd k8s/overlays/eks
IMAGE_TAG=<git-sha-from-ci-or-script> ./deploy.sh
```

If you need manual Terraform order, read [`docs/DEPLOYMENT-ORDER.md`](docs/DEPLOYMENT-ORDER.md) and [`terraform/README.md`](terraform/README.md).

### 3. AKS Path

```bash
./spinup.sh
# Choose: aks
```

Then deploy with `k8s/overlays/aks` as described in [`README.md`](README.md).

Also read [`docs/AKS-AMQP-INCOMPATIBILITY.md`](docs/AKS-AMQP-INCOMPATIBILITY.md).

### 4. CI/CD

Read:

- [`.github/workflows/build-and-deploy.yml`](.github/workflows/build-and-deploy.yml)
- [`docs/cicd-local.md`](docs/cicd-local.md)
- [`docs/README.md`](docs/README.md), CI/CD section

Week 4 is done when you can describe this chain:

```text
git push -> image build -> registry -> manifest/deploy -> running pods
```

## When Things Go Wrong

Start here:

1. `./scripts/validate.sh`
2. [`docs/README.md`](docs/README.md)
3. [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md)
4. [`docs/troubleshooting.md`](docs/troubleshooting.md)

Environment-specific help:

| Environment | Start with |
|-------------|------------|
| Compose | `TROUBLESHOOTING.md`, Docker section |
| MicroK8s | `TROUBLESHOOTING.md` and [MicroK8s deployment guide](https://osomudeya.gumroad.com/l/payflow) |
| EKS / AKS | `TROUBLESHOOTING.md` and [`docs/DEPLOY-TROUBLESHOOTING.md`](docs/DEPLOY-TROUBLESHOOTING.md) |

## Quick Reference

| I want to | Go to |
|-----------|-------|
| Follow the curriculum | This file |
| Pick the right doc | [`docs/README.md`](docs/README.md) |
| Run on Kubernetes | `./scripts/deploy-microk8s.sh` |
| Run without Kubernetes | `docker compose up -d` |
| Understand money flow | [`docs/system-flow.md`](docs/system-flow.md) |
| Understand architecture | [`docs/architecture.md`](docs/architecture.md) |
| Practice failure drills | [`docs/HOME-LAB-DRILLS.md`](docs/HOME-LAB-DRILLS.md) |
| Start AWS | [`docs/INFRASTRUCTURE-ONBOARDING.md`](docs/INFRASTRUCTURE-ONBOARDING.md), then `./spinup.sh` |
| Deploy or roll back app | [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) |

## You Are Done When

You can do these without reading from the docs:

- Run PayFlow locally and validate it.
- Explain the money path from browser to database to notification.
- Explain Ingress, Service, Deployment, and overlay.
- Kill a pod and explain why Kubernetes recovers it.
- Trace one request with a correlation ID.
- Explain idempotency and why retries are dangerous without it.
- Read one NetworkPolicy and describe what it blocks.
- Describe the CI/CD path from `git push` to running pod.
- Provision cloud infra in the documented order and tear it down safely.

Resume prep: choose two items above and turn each into one honest sentence starting with "Built", "Deployed", "Debugged", or "Automated".
