output "cluster_name" {
  value = module.eks.cluster_name
}

output "configure_kubectl" {
  description = "Run this to point kubectl at the new cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "ecr_repository_urls" {
  value = { for k, v in aws_ecr_repository.this : k => v.repository_url }
}

output "rds_endpoint" {
  value = module.db.db_instance_address
}

output "s3_events_bucket" {
  value = aws_s3_bucket.ops_data.bucket
}

output "lambda_function_name" {
  value = aws_lambda_function.process_event.function_name
}

output "argocd_initial_admin_password_command" {
  description = "ArgoCD's auto-generated admin password lives in a secret - fetch it with this"
  value       = "kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "argocd_port_forward_command" {
  value = "kubectl -n argocd port-forward svc/argocd-server 8080:443"
}
