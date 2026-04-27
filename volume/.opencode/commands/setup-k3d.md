---
description: Setup kubeopencode on k3d
---
1. Delete existing cluster if it exists: `k3d cluster delete opencode-cluster || true`
2. Run setup.sh

This task is successful when:

- setup.sh completes without errors
- Kubeopencode is accessible at http://<IP ADDRESS>:8000
- Agent is running and ready
- Task completes successfully
- LLM response is correct on each task

DO NOT RUN ANY OTHER MANUAL STEPS.
If steps are not sufficient, provide suggestions for updates, but do not update until user confirms changes.