# Deploying OpenCode on k3d

## Prerequisites

- k3d installed
- kubectl installed

## Steps

### 1. Create a k3d cluster (if you don't have one)

```bash
mkdir -p workspace
k3d cluster create opencode-cluster -v $(pwd)/workspace:/workspace -p 8080:80@loadbalancer
```

### 2. Install kubeopencode to the cluster

```bash
kubectl create namespace kubeopencode-system
helm install kubeopencode oci://quay.io/kubeopencode/helm-charts/kubeopencode -n kubeopencode-system --set server.enabled=true
```

### 3. Create secrets

Create the secret from the API key file:

```bash
API_KEY=$(cat /path/to/your-api-key.file) && kubectl create secret generic opencode-credentials --from-literal=OPENCODE_API_KEY="$API_KEY" --dry-run=client -o yaml > secrets.output.yaml
kubectl apply -f secrets.output.yaml
```

### 4. Create ServiceAccount for the Agent

```bash
kubectl apply -f deploy/serviceaccount.yaml
```

### 5. Apply RBAC fix (if needed)

```bash
# The helm chart may be missing some permissions. Apply additional RBAC:
kubectl get clusterrole kubeopencode-controller -o json | jq '.rules[2].resources += ["persistentvolumeclaims"]' | kubectl apply -f -
# Then restart controller
kubectl rollout restart deployment kubeopencode-controller -n kubeopencode-system
```

### 6. Create an Agent

Create `deploy/agent.yaml`:

```yaml
apiVersion: kubeopencode.io/v1alpha1
kind: Agent
metadata:
  name: opencode-agent
spec:
  config: |
    {
      "$schema": "https://opencode.ai/config.json",
      "model": "opencode/big-pickle"
    }
  credentials:
    - name: opencode
      secretRef:
        name: opencode-credentials
  workspaceDir: /workspace
  serviceAccountName: opencode-agent
```

Apply:

```bash
kubectl apply -f deploy/agent.yaml
```

### 7. Create Ingress (for external access)

```bash
kubectl apply -f deploy/ingress.yaml
```

Or inline:

```bash
kubectl create ingress opencode --class=traefik --rule="/*=opencode:4096"
```

### 8. Verify deployment

```bash
# Check pods
kubectl get pods -n kubeopencode-system
kubectl get pods -n default

# Check agent
kubectl get agents
kubectl get deployment -n default
```

### 9. Access the service

Open `http://localhost:8080` in your browser.

### 10. (Optional) Check logs

```bash
kubectl logs -n kubeopencode-system -l app=kubeopencode-controller
```

## Cleanup

```bash
kubectl delete -f deploy/agent.yaml
kubectl delete -f deploy/serviceaccount.yaml
kubectl delete secret opencode-credentials
helm uninstall kubeopencode -n kubeopencode-system
k3d cluster delete opencode-cluster
rm -rf workspace
```