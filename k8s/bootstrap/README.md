# Bootstrap manifests

These are applied manually, once, before ArgoCD exists to manage anything
itself:

    kubectl apply -n argocd -f k8s/bootstrap/argocd-ingress.yaml
    kubectl apply -n argocd -f k8s/argocd-apps/root.yaml

After that, ArgoCD reconciles everything else in this repo on its own.
