#!/bin/bash
set -e

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG="/tmp/kubeconfig"
export KUBECONFIG

CLUSTER_NAME="opencode-cluster"

KUBEOPENCODE_CHART_VERSION="0.0.28"
KUBEOPENCODE_AGENT_OPENCODE_VERSION="v0.0.28"
KUBEOPENCODE_AGENT_DEVBOX_VERSION="v0.0.28"
KUBEOPENCODE_AGENT_ATTACH_VERSION="v0.0.28"
export CLUSTER_NAME

echo "=== Creating k3d cluster ==="
mkdir -p "${WORKSPACE_DIR}/workspace"
k3d cluster list | grep -q "${CLUSTER_NAME}" || k3d cluster create "${CLUSTER_NAME}" -v "${WORKSPACE_DIR}/workspace:/workspace" -p 8000:80@loadbalancer

echo "=== Pulling and importing agent images ==="
for img in ghcr.io/kubeopencode/kubeopencode-agent-opencode:${KUBEOPENCODE_AGENT_OPENCODE_VERSION} ghcr.io/kubeopencode/kubeopencode-agent-devbox:${KUBEOPENCODE_AGENT_DEVBOX_VERSION} ghcr.io/kubeopencode/kubeopencode-agent-attach:${KUBEOPENCODE_AGENT_ATTACH_VERSION}; do
    docker pull "${img}"
    k3d image import "${img}" -c "${CLUSTER_NAME}"
done

echo "=== Getting kubeconfig ==="
k3d kubeconfig get "${CLUSTER_NAME}" > "${KUBECONFIG}"

echo "=== Applying namespace ==="
kubectl apply -f "${WORKSPACE_DIR}/deploy/namespace.yaml"

echo "=== Upgrading helm chart ==="
helm upgrade kubeopencode oci://ghcr.io/kubeopencode/helm-charts/kubeopencode -n kubeopencode-system --version "${KUBEOPENCODE_CHART_VERSION}" --set server.enabled=true --set controller.image.pullPolicy=Always || \
helm install kubeopencode oci://ghcr.io/kubeopencode/helm-charts/kubeopencode -n kubeopencode-system --version "${KUBEOPENCODE_CHART_VERSION}" --set server.enabled=true

echo "=== Applying CRDs ==="
kubectl apply -f https://raw.githubusercontent.com/kubeopencode/kubeopencode/main/deploy/crds/kubeopencode.io_agenttemplates.yaml
kubectl apply -f https://raw.githubusercontent.com/kubeopencode/kubeopencode/main/deploy/crds/kubeopencode.io_crontasks.yaml

echo "=== Applying namespaces ==="
kubectl apply -f "${WORKSPACE_DIR}/deploy/namespace.yaml"

echo "=== Creating credentials secret ==="
API_KEY_FILE="/mnt/vm-shared-volume/.config/opencode/secrets/opencode-zen.key"
if [ -f "${API_KEY_FILE}" ]; then
  API_KEY=$(cat "${API_KEY_FILE}")
  kubectl create secret generic opencode-credentials --from-literal=OPENCODE_API_KEY="${API_KEY}" -n kubeopencode-default --dry-run=client -o yaml | tee "${WORKSPACE_DIR}/deploy/secrets/credentials.yaml" | kubectl apply -f -
else
  echo "Warning: API key file not found at ${API_KEY_FILE}"
fi

echo "=== Applying ServiceAccount ==="
kubectl apply -f "${WORKSPACE_DIR}/deploy/serviceaccount.yaml"

echo "=== Creating Agent ==="
kubectl apply -f "${WORKSPACE_DIR}/deploy/agent.yaml"

echo "=== Waiting for agent to be ready ==="
for i in {1..60}; do
    READY=$(kubectl get agent opencode-agent -n kubeopencode-default -o jsonpath='{.status.ready}' 2>/dev/null | tr '[:upper:]' '[:lower:]')
    if [ "$READY" = "true" ]; then
        echo "Agent is ready"
        break
    fi
    echo "Waiting for agent... ($i/60)"
    sleep 2
done

echo "=== Applying test tasks ==="
kubectl apply -f "${WORKSPACE_DIR}/deploy/tasks/"

echo "=== Waiting for cleanup-test to complete ==="
for i in {1..60}; do
    PHASE=$(kubectl get task cleanup-test -n kubeopencode-default -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$PHASE" = "Completed" ] || [ "$PHASE" = "Failed" ]; then
        echo "Task phase: $PHASE"
        break
    fi
    echo "Waiting for task... ($i/60) - Phase: $PHASE"
    sleep 2
done

kubectl get task cleanup-test -n kubeopencode-default

echo "=== Waiting for configure-opencode-test to complete ==="
for i in {1..60}; do
    PHASE=$(kubectl get task configure-opencode-test -n kubeopencode-default -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$PHASE" = "Completed" ] || [ "$PHASE" = "Failed" ]; then
        echo "Task phase: $PHASE"
        break
    fi
    echo "Waiting for task... ($i/60) - Phase: $PHASE"
    sleep 2
done

kubectl get task configure-opencode-test -n kubeopencode-default

echo "=== Applying Ingress ==="
kubectl apply -f "${WORKSPACE_DIR}/deploy/ingress.yaml"

echo "=== Server accessible at: http://$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'):8000 ==="