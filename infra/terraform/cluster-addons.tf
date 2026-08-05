# ---------------------------------------------------------------------------
# IRSA role for the AWS Load Balancer Controller (the thing that turns your
# k8s Ingress into a real ALB). The module handles the (long) official IAM
# policy internally.
# ---------------------------------------------------------------------------
module "alb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "5.44.0"

  role_name = "${var.project}-alb-controller"

  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "kubernetes_service_account" "alb_controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
      "app.kubernetes.io/component" = "controller"
    }
    annotations = {
      "eks.amazonaws.com/role-arn" = module.alb_controller_irsa.iam_role_arn
    }
  }

  depends_on = [module.eks]
}

resource "helm_release" "aws_load_balancer_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.8.1"

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = kubernetes_service_account.alb_controller.metadata[0].name
  }
  set {
    name  = "region"
    value = var.aws_region
  }
  set {
    name  = "vpcId"
    value = module.vpc.vpc_id
  }

  depends_on = [kubernetes_service_account.alb_controller]
}

# ---------------------------------------------------------------------------
# ArgoCD - installed by Terraform so the GitOps loop is bootstrapped
# automatically. It then owns the actual application deployments.
# ---------------------------------------------------------------------------
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = "7.3.11"

  # Keep this a lean, demo-appropriate install. For real prod, split into
  # HA components and put values in their own file.
  set {
    name  = "configs.params.server\\.insecure"
    value = "true" # ALB/Ingress terminates TLS; simplifies the demo
  }
}

# App namespaces that the ArgoCD Applications (k8s/argocd-apps/*.yaml) deploy into.
resource "kubernetes_namespace" "staging" {
  metadata { name = "staging" }
}

resource "kubernetes_namespace" "prod" {
  metadata { name = "prod" }
}

resource "kubernetes_namespace" "monitoring" {
  metadata { name = "monitoring" }
}
# The app's DB credentials, created directly as k8s Secrets so nobody has to
# hand-copy the RDS password. One per environment namespace.
resource "kubernetes_secret" "db_secret" {
  for_each = toset(["staging", "prod"])

  metadata {
    name      = "db-secret"
    namespace = each.key
  }

  data = {
      url = "postgresql://${var.db_username}:${random_password.db.result}@${module.db.db_instance_address}:5432/${var.db_name}?sslmode=require"  }

  depends_on = [kubernetes_namespace.staging, kubernetes_namespace.prod]
}