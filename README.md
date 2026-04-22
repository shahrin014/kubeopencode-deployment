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

### 3. Create ConfigMap from opencode.json

Create `volume/.opencode/opencode.json` locally:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "provider": {
    "opencode": {
      "options": {
        "apiKey": "{env:OPENCODE_API_KEY}"
      }
    }
  },
  "command": {
    "cleanup": {
      "template": "Find and remove outdated files in the project. Look for:\n- Temporary files (e.g., *.tmp, *.bak, *.swp)\n- Build artifacts (e.g., node_modules, dist, build, __pycache__)\n- Generated files that are no longer needed\n- Old log files\n\nList the files found and ask for confirmation before deleting them.",
      "description": "Clean up outdated and temporary files"
    }
  }
}
```

Generate a ConfigMap from the file:

```bash
kubectl create configmap opencode-config --from-file=opencode.json=volume/.opencode/opencode.json --dry-run=client -o yaml > configmap.output.yaml
kubectl apply -f configmap.output.yaml
```

### 4. Create secrets

Create the secret from the API key file:

```bash
API_KEY=$(cat /path/to/your-api-key.file) && kubectl create secret generic opencode-credentials --from-literal=OPENCODE_API_KEY="$API_KEY" --dry-run=client -o yaml > secrets.output.yaml
kubectl apply -f secrets.output.yaml
```

### 5. Create ServiceAccount for the Agent

```bash
kubectl apply -f deploy/serviceaccount.yaml
```

### 6. Apply RBAC fix (if needed)

```bash
# The helm chart may be missing some permissions. Apply additional RBAC:
kubectl get clusterrole kubeopencode-controller -o json | jq '.rules[2].resources += ["persistentvolumeclaims"]' | kubectl apply -f -
# Then restart controller
kubectl rollout restart deployment kubeopencode-controller -n kubeopencode-system
```

### 7. Create an Agent

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

### 8. Create Ingress (for external access)

```bash
kubectl apply -f deploy/ingress.yaml
```

Or inline:

```bash
kubectl create ingress opencode --class=traefik --rule="/*=opencode:4096"
```

### 9. Verify deployment

```bash
# Check pods
kubectl get pods -n kubeopencode-system
kubectl get pods -n default

# Check agent
kubectl get agents
kubectl get deployment -n default
```

### 10. Access the service

Open `http://localhost:8080` in your browser.

### 11. (Optional) Check logs

```bash
kubectl logs -n kubeopencode-system -l app=kubeopencode-controller
```

## Cleanup

```bash
kubectl delete -f deploy/agent.yaml
kubectl delete -f deploy/serviceaccount.yaml
kubectl delete configmap opencode-config
kubectl delete secret opencode-credentials
helm uninstall kubeopencode -n kubeopencode-system
k3d cluster delete opencode-cluster
rm -rf workspace
```