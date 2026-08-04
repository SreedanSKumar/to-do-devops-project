# OpsBoard - Demo / Presentation Outline

Use this as your talk track. Aim for ~10-15 minutes: architecture (3 min),
live GitOps deploy (5 min), observability (4 min), rollback (2 min).

## 1. Architecture (slide + diagram from README.md)

- Two-tier app: frontend (Express, static UI + reverse proxy) and backend
  (Express + Postgres), each containerized, each with its own Deployment/
  Service/HPA in EKS.
- Browser only ever talks to the frontend (via ALB Ingress); the frontend
  proxies `/api/*` to the backend's ClusterIP Service. Backend and RDS are
  never internet-reachable - call this out, it's a real security decision,
  not an accident.
- Terraform provisions infra (VPC, EKS, RDS, ECR, S3, Lambda) and the
  *platform* layer (ALB controller, ArgoCD) via Helm. ArgoCD then owns every
  application workload from Git. That split - Terraform for infra,
  ArgoCD/GitOps for workloads - is the core architectural decision to
  narrate.

## 2. Live GitOps deploy

1. Make a trivial visible change (e.g. edit the UI subtitle text in
   `app/frontend/public/index.html`) and push to `main`.
2. Show the GitHub Actions run: test job → build/scan/push to ECR → the
   commit it makes to `k8s/overlays/staging/kustomization.yaml`.
3. Show ArgoCD's UI: `opsboard-staging` Application goes `OutOfSync` →
   `Syncing` → `Healthy` on its own, no manual kubectl.
4. Load the staging URL, show the change live.
5. Run the "Promote Staging to Production" workflow manually - narrate that
   this is the deliberate approval gate between staging and prod.

## 3. Observability

1. Open Grafana, show the OpsBoard dashboard: request rate, p95 latency,
   error ratio, restart count - all sourced from the backend's own
   `/metrics` endpoint via a Prometheus `ServiceMonitor`.
2. Add a few tasks / hit the API a few times to move the graphs live.
3. Open Grafana Explore → Loki, filter to `{app="backend"}`, show live logs
   flowing in via Promtail with no app-side logging integration needed.
4. Show `k8s/base/alerts.yaml` - walk through one rule (e.g. high error
   rate) and explain the PromQL in plain English.

## 4. Rollback

1. Trigger the "GitOps Rollback" workflow against `staging`, giving it the
   commit SHA from before your demo change.
2. Show ArgoCD reconcile the overlay back down; reload the staging URL to
   confirm the change is gone.
3. Narrate: rollback is just another Git commit, so it's auditable and
   reviewable exactly like a deploy is.

## 5. Serverless bonus (if time allows)

`aws s3 cp` a file into the events bucket, `aws logs tail` the Lambda's log
group live to show the S3 → Lambda trigger firing.

## Anticipated questions

- **"Why kustomize instead of separate Helm charts per env?"** - Base +
  overlay avoids duplicating the whole manifest set for two nearly-identical
  environments; only the actual differences (replica count, namespace,
  image tag) live in the overlay.
- **"What happens if ArgoCD's Helm-chart-based monitoring apps sync after
  the app itself?"** - `k8s/base/servicemonitor.yaml` and `alerts.yaml`
  reference the Prometheus Operator's CRDs. The monitoring Applications
  carry a lower `sync-wave` so they land first; if they didn't, ArgoCD would
  just retry those specific resources on its next `selfHeal` pass once the
  CRDs exist - it wouldn't block the rest of the app from deploying.
- **"Why generate the DB password instead of hardcoding it?"** - the
  original scaffold had `password123` in plaintext in `docker-compose.yml`
  and implied the same for RDS. `random_password` + a Kubernetes Secret
  created directly by Terraform means nobody ever types or commits the real
  credential.
