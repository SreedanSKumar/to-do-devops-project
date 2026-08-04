# OpsBoard - Cloud-Native Capstone

A containerized to-do list app (Node/Express frontend + Node/Express/Postgres
backend), deployed to AWS EKS via Terraform + GitHub Actions + ArgoCD, with
Prometheus/Grafana/Loki observability and a Lambda triggered by S3.

## Architecture

```
                                   ┌─────────────────────────────────────┐
                                   │                AWS                   │
  Browser ──HTTPS──► ALB (Ingress) │                                       │
                        │          │  ┌──────────────┐    ┌─────────────┐ │
                        ├─/──────► │  │  frontend pod │    │  backend pod │ │
                        └─/api───► │  │ (Express, proxy)│─►│(Express+pg)  │ │
                                   │  └──────────────┘    └──────┬──────┘ │
                                   │        EKS (private subnets) │        │
                                   │                               ▼        │
                                   │                          RDS Postgres  │
                                   │                        (private subnet)│
                                   │                                       │
                                   │  S3 bucket ──ObjectCreated──► Lambda   │
                                   │                                       │
                                   │  Prometheus ◄─scrape── backend /metrics│
                                   │  Grafana  ◄─dashboards/alerts          │
                                   │  Loki ◄─promtail── pod logs            │
                                   └─────────────────────────────────────┘

  GitOps loop:
  GitHub push → Actions (test, build, scan, push to ECR, update k8s/overlays/staging)
             → ArgoCD (auto-syncs staging) → manual "Promote to Production" workflow
             → ArgoCD (auto-syncs prod)
```

Design choices worth calling out in your demo:
- **The browser never talks to the backend directly.** It only ever calls
  same-origin `/api/...`; the frontend container proxies that to the
  internal `backend-svc` ClusterIP. This works identically in
  docker-compose and in EKS, and means the backend Service and RDS instance
  never need to be internet-reachable.
- **Terraform owns infrastructure, ArgoCD owns workloads.** Terraform
  provisions VPC/EKS/RDS/ECR/S3/Lambda and installs the *platform* Helm
  charts (ALB controller, ArgoCD itself). Everything under `k8s/` is then
  reconciled by ArgoCD from Git - that's the actual GitOps loop.
- **Staging and prod are kustomize overlays of the same base**, not
  duplicated YAML. CI auto-deploys to staging on every push to `main`;
  promotion to prod is a deliberate, separate, manual workflow.

## Repo layout

```
app/                  frontend + backend source, Dockerfiles
infra/terraform/      VPC, EKS, RDS, ECR, IRSA, ALB controller, ArgoCD, Lambda
k8s/base/             deployments, services, ingress, HPA, ServiceMonitor,
                       PrometheusRule, Grafana dashboard
k8s/overlays/staging/ namespace + replica-count patch + image tags for staging
k8s/overlays/prod/    same, for prod
k8s/argocd-apps/      ArgoCD Application manifests (app-of-apps root + children)
.github/workflows/    CI/CD, promotion, rollback
```

## Prerequisites

- AWS account with credentials capable of creating VPC/EKS/RDS/IAM/S3/Lambda
- Terraform >= 1.5, AWS CLI v2, `kubectl`, `kustomize`, `helm` (helm only if
  you want to inspect charts locally - Terraform installs them into the
  cluster for you)
- A GitHub repo containing this code, with these Actions secrets set:
  `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`

Before anything else, replace every `REPLACE_WITH_YOUR_ACCOUNT_ID` in
`k8s/base/*.yaml`, `k8s/overlays/*/kustomization.yaml`, and both GitHub
workflows with your real AWS account ID (or template it - see "Improvements"
below). Also replace `yourorg/yourrepo` in every `k8s/argocd-apps/*.yaml`
with your actual GitHub repo URL.

## 1. Provision infrastructure

```bash
cd infra/terraform
terraform init
terraform plan
terraform apply
```

This creates the VPC, EKS cluster, RDS instance, ECR repos, S3 bucket +
Lambda, and installs the AWS Load Balancer Controller and ArgoCD into the
cluster via Helm. It also creates the `staging`, `prod`, and `monitoring`
namespaces and a `db-secret` in each app namespace with the real RDS
connection string - you never type or commit a DB password.

```bash
aws eks update-kubeconfig --region ap-south-1 --name opsboard-cluster
kubectl get nodes   # sanity check
```

## 2. Bootstrap ArgoCD (GitOps)

```bash
kubectl apply -n argocd -f k8s/argocd-apps/root.yaml
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
kubectl -n argocd port-forward svc/argocd-server 8080:443
# open https://localhost:8080, log in as admin
```

The root Application then manages every other Application in
`k8s/argocd-apps/` - monitoring stack, staging, and prod - all from Git.

## 3. First image build

The very first push to `main` (after secrets are set) runs the CI/CD
pipeline: tests → build → Trivy scan → push to ECR → update
`k8s/overlays/staging/kustomization.yaml` with the new image tags → commit.
ArgoCD picks up that commit and rolls staging out automatically.

To promote what's on staging to prod, run the **"Promote Staging to
Production"** workflow manually from the Actions tab - that's the approval
gate.

## 4. Rollback

Run the **"GitOps Rollback"** workflow, choose `staging` or `prod`, and give
it the commit SHA to revert that overlay to. It reverts just that overlay
directory and pushes; ArgoCD's `selfHeal` converges the cluster back within
its next sync.

## 5. Local development

```bash
cp .env.example .env   # optional, has sane defaults already
docker compose up --build
# frontend: http://localhost:3000
# backend directly:  http://localhost:5000/api/tasks
```

## 6. Observability

Grafana, Prometheus, and Loki are deployed by the `kube-prometheus-stack`
and `loki-stack` ArgoCD Applications (Helm charts, GitOps-managed).

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3001:80
# user: admin / password: value of grafana.adminPassword in
# k8s/argocd-apps/monitoring-kube-prometheus-stack.yaml (change it before a
# real deployment - it's a demo placeholder, not a secret you should keep)
```

- The **"OpsBoard - Backend"** dashboard (auto-loaded via the Grafana
  sidecar) shows request rate, p95 latency, 5xx ratio, and pod restarts.
- Alerts (`k8s/base/alerts.yaml`): backend target down, 5xx rate > 5%, p95
  latency > 1s, pod crash-looping. They route through Alertmanager - wire up
  a receiver (Slack/email/PagerDuty) in the `kube-prometheus-stack` values
  for a real deployment.
- Loki + Promtail ship every pod's stdout/stderr logs; explore them from
  Grafana's "Explore" tab with the Loki datasource.

## 7. Serverless (Lambda + S3)

Drop any object into the bucket named in `terraform output
s3_events_bucket` and the Lambda function logs a structured event to
CloudWatch Logs:

```bash
aws s3 cp somefile.txt s3://$(terraform -chdir=infra/terraform output -raw s3_events_bucket)/
aws logs tail /aws/lambda/opsboard-process-event --follow
```

## Known limitations / what a real production version would add

- Single NAT gateway (cost-saver for a demo) instead of one per AZ
- RDS `multi_az = false`, `deletion_protection = false`,
  `skip_final_snapshot = true` - flip all three for real prod
- No TLS on the ALB (HTTP only) - add an ACM cert + HTTPS listener
- Grafana admin password is a plaintext placeholder in the Application
  manifest - move it to a real Secret (e.g. via External Secrets Operator
  against AWS Secrets Manager) before this ever sees a real user
- `REPLACE_WITH_YOUR_ACCOUNT_ID` / `yourorg/yourrepo` placeholders are
  manual find-and-replace; a templating step (e.g. a Makefile or
  `envsubst` pass) would remove that manual step entirely
