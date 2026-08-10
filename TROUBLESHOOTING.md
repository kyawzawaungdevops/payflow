# PayFlow Troubleshooting Guide — Quick Fix Reference

> **This is the fast one.** Every failure mode found during a full system audit, presented as symptom → root cause → exact fix. No narrative, just solutions.
>
> Run `./scripts/validate.sh` first — it will tell you which layer is broken.
>
> Need deeper explanations with underlying concepts and real-world failure stories? See [`docs/troubleshooting.md`](docs/troubleshooting.md).
>
> **Which guide should I open?** See the [documentation index](docs/README.md) — deploy vs debug vs learn.
>
> **Learning path:** [`LEARNING-PATH.md`](LEARNING-PATH.md) runs **MicroK8s first**; Docker Compose is optional. Many fixes below are labeled **Docker Compose** vs **MicroK8s**—use the section that matches how you run the app.

---

## Docker Compose

### api-gateway exits immediately on startup

**Symptom:**
```
payflow-api-gateway exited with code 1
Error: DB_PASSWORD must be set (api-gateway health check requires database access)
```

**Root cause:** The api-gateway health check pool needs database credentials at module load.

**Fix:** Ensure the `api-gateway` environment block in `docker-compose.yml` includes:
```yaml
DB_HOST: postgres
DB_PORT: 5432
DB_NAME: payflow
DB_USER: payflow
DB_PASSWORD: payflow123
```
This is already present in the current `docker-compose.yml`. If you see this error, you may have an old version — pull latest.

---

### Frontend loads but all API calls fail (Network Error / CORS)

**Symptom:** React app loads at `http://localhost`, buttons spin, errors in the browser console like `ERR_CONNECTION_REFUSED` or CORS errors.

**Root cause:** The frontend image was built with `REACT_APP_API_URL=http://localhost:3000/api` baked in (old build), and the api-gateway is not reachable via that URL, OR CORS is misconfigured.

**Fix:**
```bash
# Force a clean rebuild (no cache)
docker compose build --no-cache frontend
docker compose up -d frontend
```
The Dockerfile default (`ARG REACT_APP_API_URL=/api`) must be used — do NOT pass `--build-arg REACT_APP_API_URL=...`.

---

### Services fail with "host not found" for postgres/redis/rabbitmq

**Symptom:** Services log `ECONNREFUSED` or `getaddrinfo ENOTFOUND postgres`.

**Root cause:** Services started before infrastructure was healthy.

**Fix:**
```bash
docker compose down
docker compose up -d postgres redis rabbitmq
sleep 15
docker compose up -d
```
The `depends_on: condition: service_healthy` directives handle this automatically on `docker compose up`, but a partial restart can leave services in the wrong order.

---

### RabbitMQ UI not accessible at localhost:15672

**Symptom:** Browser shows "connection refused" at `http://localhost:15672`.

**Root cause:** The `rabbitmq:3-management-alpine` image is used. If the container hasn't started yet, or the management plugin needs time to initialise, the UI isn't available immediately.

**Fix:**
```bash
docker compose logs rabbitmq
# Wait for: "Server startup complete"
```

---

## MicroK8s / Kubernetes

### api-gateway in CrashLoopBackOff

**Symptom:**
```
kubectl logs -n payflow deploy/api-gateway
Error: DB_PASSWORD must be set
```

**Root cause:** The `db-secrets` Secret doesn't exist or doesn't contain `DB_PASSWORD`.

**Fix (local overlay):**
```bash
kubectl get secret db-secrets -n payflow
# If not found:
kubectl apply -k k8s/overlays/local
# db-secrets is defined in k8s/overlays/local/secrets-db-secrets.yaml
```

**Fix (EKS — ESO not synced yet):**
```bash
kubectl describe externalsecret db-secrets-external -n payflow
# Look for: "SecretSyncedError" or "Store not ready"
# ESO needs a few minutes after install. Check:
kubectl get pods -n external-secrets
```

---

### Pods stuck in Pending

**Symptom:** `kubectl get pods -n payflow` shows `Pending` for multiple pods.

**Root cause A — ResourceQuota exceeded:**
```bash
kubectl describe quota -n payflow
# If used == hard, the quota is exhausted
```
**Fix:** The local overlay applies `local-quota-patch.yaml` which raises limits. Ensure you applied the overlay, not just the base:
```bash
kubectl apply -k k8s/overlays/local   # not: kubectl apply -k k8s/base
```

**Root cause B — Node has insufficient resources:**
```bash
kubectl describe node | grep -A5 "Allocated resources"
```
Stop other processes or increase the MicroK8s VM memory.

---

### Frontend returns 502 for all /api/* requests

**Symptom:** Frontend loads, but every API call returns a 502 Bad Gateway.

**Root cause:** api-gateway is not Ready (see CrashLoopBackOff above), or nginx can't resolve `api-gateway.payflow.svc.cluster.local`.

**Fix:**
```bash
# Check api-gateway pod status
kubectl get pods -n payflow -l app=api-gateway

# Check nginx resolver (MicroK8s DNS addon must be enabled)
microk8s enable dns

# Check nginx config inside the frontend pod
kubectl exec -n payflow deploy/frontend -- cat /etc/nginx/conf.d/default.conf
# Should contain: resolver 10.152.183.10 valid=10s;  (IP, not hostname — nginx only accepts IPs)
# and: set $api_upstream "http://api-gateway.payflow.svc.cluster.local:80";
#      proxy_pass $api_upstream;  (variable forces lazy DNS, prevents startup crash)
```

---

### "Transaction failed: Message queue unavailable — please retry"

**Symptom:** The frontend Send Money form returns this error. The transaction service logs show:
```
error: Transaction creation failed: {"error":"Message queue unavailable — please retry"}
```
The RabbitMQ pod is `Running` and healthy, but the transaction service cannot reach it.

**Root cause:** Kubernetes `NetworkPolicy` is blocking port 5672 (plain AMQP). The base network policies were originally written for Amazon MQ on EKS which uses port **5671** (TLS). The `default-deny-all` policy silently drops all traffic on 5672, causing TCP timeouts the service reports as "queue unavailable."

You can confirm the block:
```bash
# From inside the transaction-service pod — this will hang/timeout if blocked
kubectl exec -n payflow deployment/transaction-service -- node -e "
const amqp = require('amqplib');
amqp.connect(process.env.RABBITMQ_URL)
  .then(() => { console.log('CONNECTED'); process.exit(0); })
  .catch(e => { console.error('FAILED:', e.message); process.exit(1); });
"
```

**Fix:** Add port 5672 to the two network policies that govern RabbitMQ traffic — `services-allow-db` (egress) and `databases-allow-ingress-from-services` (ingress). The current base manifests already include this fix. If you hit this on an older checkout:
```bash
# Apply the overlay — network policies take effect immediately, no pod restart needed
kubectl apply -k k8s/overlays/local

# Verify the fix
kubectl get networkpolicy services-allow-db -n payflow -o yaml | grep "port:"
# Should show both 5672 and 5671
```

**Why both ports?** Port 5671 stays in the policy for EKS/Amazon MQ (TLS); port 5672 is needed locally. Opening a port in a NetworkPolicy is permissive — it doesn't force traffic to use it, so having both is safe.

---

### Ingress returns 404 for everything

**Symptom:** `curl http://www.payflow.local` returns 404.

**Root cause:** `/etc/hosts` entry missing, or wrong ingress class.

**Fix:**
```bash
# Add hosts entries
bash scripts/setup-hosts-payflow-local.sh

# Verify ingress controller is running
kubectl get pods -n ingress

# Verify ingress rule
kubectl describe ingress -n payflow
```
The local overlay ingress uses `ingressClassName: public` (MicroK8s). If your cluster uses `nginx`, update `k8s/overlays/local/ingress-local.yaml`.

---

### Stuck pending transactions (CronJob timeout)

**Symptom:** The UI shows one or more transactions stuck in **PENDING** for a long time, or metrics like `payflow_pending_transactions_total` stay above zero when they should clear after the timeout window.

**What should happen:** The **`transaction-timeout-handler` CronJob** is Kubernetes’ way of running a command on a schedule—it should wake up on its schedule, connect to PostgreSQL, and flip old pending rows to a terminal state (failed or reversed) so user balances are not left in limbo.

**Diagnosis (run in order):**

```bash
# 1) Is the CronJob defined at all?
kubectl get cronjobs -n payflow

# 2) Are Jobs being created and finishing?
kubectl get jobs -n payflow | grep transaction-timeout || true
kubectl describe cronjob transaction-timeout-handler -n payflow 2>/dev/null || true

# 3) If Job pods exist, read logs from the newest timeout-handler pod:
kubectl get pods -n payflow | grep transaction-timeout
# Then: kubectl logs -n payflow <pod-name-from-list-above> --tail=80
```

**Common causes:**

1. **CronJob never applied** — The manifest existed in git but `kubectl apply` never put it in the cluster. Fix: apply the same overlay you use for the app (`kubectl apply -k k8s/overlays/local` for MicroK8s, or your cloud overlay deploy path) and re-check `kubectl get cronjobs`.

2. **ResourceQuota blocked the Job pod** — If you see `forbidden: failed quota ... must specify limits.cpu` (or memory) when describing the Job, the CronJob’s pod template needs explicit **`resources.requests` and `resources.limits`** so the scheduler can admit the pod under `payflow-resource-quota`.

3. **Job pod cannot reach Postgres (DNS / NetworkPolicy)** — Short-lived Job pods sometimes fail DNS to `postgres.payflow.svc.cluster.local` while long-lived app pods work. When that happens, **exec into the Postgres pod** (which is already on the network you trust) and run SQL there—this is the reliable escape hatch:

```bash
# List stuck rows
kubectl exec -n payflow postgres-0 -- psql -U payflow -d payflow -c \
  "SELECT id, status, created_at FROM transactions WHERE status = 'PENDING' ORDER BY created_at DESC LIMIT 20;"

# Emergency reversal (only after you understand the row—you are changing money state)
kubectl exec -n payflow postgres-0 -- psql -U payflow -d payflow -c \
  "UPDATE transactions SET status = 'FAILED', error_message = 'Transaction timeout - operator reversed', completed_at = CURRENT_TIMESTAMP WHERE status = 'PENDING' AND created_at < NOW() - INTERVAL '5 minutes';"
```

**CoreDNS / DNS:** If Job logs show `could not translate host name` or DNS timeouts, confirm `microk8s enable dns` (local) and that **NetworkPolicies** allow the Job’s service account / labels to reach the database Service and UDP/TCP 53 to CoreDNS—compare with a working app pod’s labels.

**Lesson learned:** Pending money is an **operations** problem, not only a code bug. You want a healthy CronJob, quota-safe pod specs, and metrics or alerts on pending count and job success—otherwise you only hear about it when a user complains.

---

### CoreDNS or cluster DNS failing

**Symptom:** Random services log “could not resolve host”, Job pods cannot reach `*.svc.cluster.local`, or alerts fire on kube-dns / CoreDNS being down.

**MicroK8s:** Run `microk8s enable dns`, then `kubectl get pods -n kube-system` and confirm CoreDNS (or the distro’s DNS pods) are `Running`. DNS is the cluster’s phone book—if it is down, every internal hostname breaks.

**Next step:** If DNS pods are healthy but app pods still fail lookups, compare **NetworkPolicies** and namespaces with a pod that *can* resolve (often the difference is labels or a deny-all policy).

---

### db-migration-job fails on EKS

**Symptom:**
```
kubectl logs -n payflow job/db-migration-job
FATAL: SSL connection is required
```

**Root cause:** Missing `PGSSLMODE=require` in the base migration job.

**Status:** The EKS overlay patch (`k8s/overlays/eks/db-migration-patch.yaml`) adds `PGSSLMODE: require`. Ensure you're applying the overlay, not the base:
```bash
IMAGE_TAG=<tag> ./k8s/overlays/eks/deploy.sh   # not: kubectl apply -k k8s/base
```

---

### EKS — kubectl times out

**Symptom:** `kubectl get nodes` hangs or returns `dial tcp: i/o timeout`.

**Root cause:** EKS cluster has `endpoint_public_access: false` — only accessible from within the VPC.

**Fix:** Open an SSH tunnel through the bastion host:
```bash
BASTION_IP=$(terraform -chdir=terraform/aws/bastion output -raw bastion_public_ip)
EKS_ENDPOINT=$(aws eks describe-cluster --name payflow-eks-cluster \
  --query 'cluster.endpoint' --output text | sed 's|https://||')
ssh -i ~/.ssh/payflow-bastion.pem \
    -L 6443:${EKS_ENDPOINT}:443 \
    ec2-user@${BASTION_IP} -N -f
```
Then retry `kubectl`.

---

### EKS — ImagePullBackOff

**Symptom:**
```
kubectl describe pod -n payflow <pod>
Failed to pull image "<ACCOUNT_ID>.dkr.ecr...": 
```

**Root cause:** `kustomization.yaml` still has literal `<ACCOUNT_ID>` / `<REGION>` / `<IMAGE_TAG>` placeholders. `kubectl apply -k` was run directly instead of via the deploy script.

**Fix:**
```bash
# Always use the deploy script, never kubectl apply -k directly on EKS:
IMAGE_TAG=<git-sha-from-ci> ./k8s/overlays/eks/deploy.sh
```

---

### AKS — Services crash with "Redis connection refused"

**Symptom:** auth-service / api-gateway logs show `ECONNREFUSED` to Redis.

**Root cause:** Azure Cache for Redis requires `rediss://` (TLS, port 6380), not `redis://`. The `REDIS_URL` in the AKS `db-secrets` Secret must use the correct scheme.

**Fix:** In Azure Key Vault, set the `payflow-redis` secret → `url` property to:
```
rediss://:YOUR_REDIS_PASSWORD@YOUR_INSTANCE.redis.cache.windows.net:6380
```
After updating Key Vault, force ESO to re-sync:
```bash
kubectl annotate externalsecret db-secrets-external -n payflow \
  force-sync=$(date +%s) --overwrite
```

---

### AKS — Pods crash with "certificate verify failed" for PostgreSQL

**Symptom:** Services log `SSL connection error: certificate verify failed`.

**Root cause:** Azure PostgreSQL Flexible Server requires SSL. The `PGSSLMODE=require` patch is applied by the AKS kustomization, but `rejectUnauthorized: false` in the service code accepts any certificate. If you see this error, the PGSSLMODE env var is missing.

**Fix:**
```bash
kubectl exec -n payflow deploy/auth-service -- env | grep PGSSLMODE
# Should print: PGSSLMODE=require
# If missing, ensure you're using the AKS overlay deploy script
```

---

## CI/CD

### GitHub Actions build passes but pods still run old image

**Root cause:** CI pushed new images to ECR/ACR, but no deploy step ran. The pipeline only builds and pushes — deployment is manual.

**Fix:** After CI completes, get the image tag from the Actions summary and run:
```bash
# EKS
IMAGE_TAG=<tag-from-ci-summary> ./k8s/overlays/eks/deploy.sh

# AKS
ACR_NAME=<your-acr> IMAGE_TAG=<tag-from-ci-summary> ./k8s/overlays/aks/deploy.sh
```

---

### GitHub Actions: "push" step skipped silently

**Symptom:** CI passes but images are not pushed to Docker Hub.

**Root cause:** `DOCKERHUB_USERNAME` secret is not set in the repository.

**Fix:** Go to GitHub → Settings → Secrets → Actions → add:
- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`

---

## Spinup and EKS infra lessons

These are the real issues we hit while wiring **`./spinup.sh`**, RDS/Redis/MQ, **External Secrets Operator (ESO)**—the component that copies AWS Secrets Manager into Kubernetes Secrets—and EKS deploys. They are folded here so you have **one** ops doc instead of a separate internal changelog.

- **Redis TLS / wrong URL** — ElastiCache expects **`rediss://`** and the right host; apps must read **`REDIS_URL`** from synced secrets, not a hardcoded `redis://` left over from local Compose.
- **RabbitMQ / Amazon MQ** — Managed brokers use **TLS** (for example port **5671** with **`amqps://`**), not plain **`amqp://`** on 5672.
- **Secrets Manager empty** — Terraform **`null_resource`** hooks write RDS/MQ/Redis endpoints into Secrets Manager after resources exist; **`spinup.sh`** verifies those keys before it lets you continue, so you do not deploy with hollow secrets.
- **Pods read DB/Redis from ConfigMap on EKS** — Base manifests were updated so sensitive endpoints come from **`db-secrets`** (via ESO); ConfigMap keeps non-secret service URLs.
- **ESO IRSA** — External Secrets needs an **IAM role for service accounts (IRSA)** so the operator can call Secrets Manager; the EKS Terraform module creates the role and **`deploy.sh`** should set the Helm service account annotation to that ARN.
- **Migration job before ESO sync** — **`deploy.sh`** waits for the ClusterSecretStore and ExternalSecret to be **Ready** before running DB migrations so the job does not start with empty **`DB_HOST`**.
- **Managed services ↔ EKS security groups** — **`managed-services`** reads EKS security group IDs from **remote Terraform state**; `spinup.sh` passes **`-var=tfstate_bucket=...`** so you do not hand-copy account IDs.
- **CI images** — EKS pulls from **ECR**; GitHub Actions can push to ECR when AWS secrets are configured (see workflow header comments).
- **EKS destroy hangs** — Leftover load balancer ENIs in public subnets can block subnet delete; see timeouts in the EKS Terraform and the **`./teardown.sh`** flow, or clean ENIs in the VPC console if Terraform times out.

For the full ordered story of what **`spinup.sh`** does, use **[`docs/INFRASTRUCTURE-ONBOARDING.md`](docs/INFRASTRUCTURE-ONBOARDING.md)**.

---

## Terraform

### `managed-services` apply fails with "no subnets found"

**Root cause:** Applied `managed-services` before `spoke-vpc-eks`. The managed services module reads VPC subnets from the spoke state.

**Fix:** Apply in the correct order:
```
hub-vpc → spoke-vpc-eks → managed-services → bastion
```
See `terraform/README.md` for the full sequence.

---

### `terraform apply` fails with "Secret may not exist yet"

**Root cause:** The `null_resource` that writes RDS credentials to Secrets Manager ran before the secret placeholder was created by `spoke-vpc-eks`.

**Fix:**
```bash
# Re-run spoke-vpc-eks first to create the Secrets Manager placeholders
cd terraform/aws/spoke-vpc-eks && terraform apply
# Then retry managed-services
cd ../managed-services && terraform apply
```

---

## General

### How do I completely reset and start fresh?

```bash
# Docker Compose
docker compose down -v --remove-orphans
docker compose up -d

# MicroK8s
kubectl delete namespace payflow
kubectl apply -k k8s/overlays/local

# EKS — delete and re-apply app layer only (leave infra)
kubectl delete namespace payflow
IMAGE_TAG=<tag> ./k8s/overlays/eks/deploy.sh
```

### How do I run the smoke test?

```bash
# Docker Compose
./scripts/validate.sh

# MicroK8s
./scripts/validate.sh --env k8s --host http://api.payflow.local

# EKS / AKS
./scripts/validate.sh --env cloud --host https://your-api-domain.com
```

---

**Done here? → Return to [`LEARNING-PATH.md`](LEARNING-PATH.md)** — pick the **week** you were in (**Week 1** MicroK8s/Compose, **Week 2** cluster, **Week 4** cloud). **Tear down cloud spend:** from repo root run **`./teardown.sh`** only (no other destroy script).

