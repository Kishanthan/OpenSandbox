# OpenSandbox on MicroK8s - Complete Deployment Guide

This guide walks you through deploying OpenSandbox on a MicroK8s cluster from scratch, including building all required images and testing the deployment.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Step 1: Prepare MicroK8s](#step-1-prepare-microk8s)
- [Step 2: Build Docker Images](#step-2-build-docker-images)
- [Step 3: Install CRDs](#step-3-install-crds)
- [Step 4: Deploy the Controller](#step-4-deploy-the-controller)
- [Step 5: Create a Pool](#step-5-create-a-pool)
- [Step 6: Create Sandboxes](#step-6-create-sandboxes)
- [Step 7: Testing with Code Interpreter Example](#step-7-testing-with-code-interpreter-example)
- [Step 8: Manual Testing](#step-8-manual-testing)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)

---

## Prerequisites

- MicroK8s installed ([installation guide](https://microk8s.io/docs/getting-started))
- Docker installed for building images
- Go 1.24+ (for building controller)
- Make
- At least 8GB RAM and 20GB disk space

---

## Quick Start

If you want to get started quickly, run these commands in order:

```bash
# 1. Enable MicroK8s addons
microk8s enable dns storage registry hostpath-storage rbac

# 2. Build and push all images (from project root)
./docs/scripts/build-microk8s-images.sh

# 3. Install CRDs and deploy controller
cd kubernetes
make install KUBECTL="microk8s kubectl"
make deploy IMG=localhost:32000/opensandbox-controller:latest \
            TASK_EXECUTOR_IMG=localhost:32000/opensandbox-task-executor:latest \
            KUBECTL="microk8s kubectl"

# 4. Create namespace and deploy sample resources
microk8s kubectl create namespace opensandbox
microk8s kubectl apply -f ../docs/microk8s/pool.yaml
microk8s kubectl apply -f ../docs/microk8s/batchsandbox.yaml

# 5. Verify
microk8s kubectl get pods -n opensandbox
```

---

## Step 1: Prepare MicroK8s

### 1.1 Enable Required Addons

```bash
# Core addons
microk8s enable dns
microk8s enable storage
microk8s enable hostpath-storage
microk8s enable rbac

# Enable the built-in registry (accessible at localhost:32000)
microk8s enable registry

# Optional but recommended
microk8s enable dashboard
microk8s enable metrics-server
```

### 1.2 Verify MicroK8s Status

```bash
microk8s status --wait-ready
```

### 1.3 Set Up kubectl Alias (Optional)

```bash
# Add to your ~/.bashrc or ~/.zshrc
alias kubectl='microk8s kubectl'
```

Or use `microk8s kubectl` directly in all commands.

### 1.4 Configure Docker for MicroK8s Registry

Add the MicroK8s registry as an insecure registry:

```bash
# Create or edit /etc/docker/daemon.json
sudo tee /etc/docker/daemon.json <<EOF
{
  "insecure-registries": ["localhost:32000"]
}
EOF

# Restart Docker
sudo systemctl restart docker
```

---

## Step 2: Build Docker Images

You need to build 4 images and push them to the MicroK8s registry.

### 2.1 Set Environment Variables

```bash
export REGISTRY="localhost:32000"
export TAG="latest"
```

### 2.2 Build Controller Image

```bash
cd kubernetes

# Build the controller
make docker-build IMG=${REGISTRY}/opensandbox-controller:${TAG}

# Push to MicroK8s registry
docker push ${REGISTRY}/opensandbox-controller:${TAG}
```

### 2.3 Build Task Executor Image

```bash
cd kubernetes

# Build task executor
make docker-build-task-executor TASK_EXECUTOR_IMG=${REGISTRY}/opensandbox-task-executor:${TAG}

# Push to registry
docker push ${REGISTRY}/opensandbox-task-executor:${TAG}
```

### 2.4 Build execd Image

```bash
cd components/execd

# Build execd
docker build -t ${REGISTRY}/opensandbox-execd:${TAG} .

# Push to registry
docker push ${REGISTRY}/opensandbox-execd:${TAG}
```

### 2.5 Build Code Interpreter Sandbox Image (Optional - Large Image)

This image is large (~5GB) and takes time to build. You can skip this and use nginx for initial testing.

```bash
cd sandboxes/code-interpreter

# Build code interpreter (this takes a while)
docker build -t ${REGISTRY}/code-interpreter:${TAG} .

# Push to registry
docker push ${REGISTRY}/code-interpreter:${TAG}
```

### 2.6 Verify Images in Registry

```bash
curl -s http://localhost:32000/v2/_catalog | jq
```

Expected output:
```json
{
  "repositories": [
    "opensandbox-controller",
    "opensandbox-task-executor",
    "opensandbox-execd",
    "code-interpreter"
  ]
}
```

---

## Step 3: Install CRDs

Custom Resource Definitions (CRDs) define the `Pool` and `BatchSandbox` resources.

```bash
cd kubernetes

# Install CRDs
make install KUBECTL="microk8s kubectl"
```

### Verify CRDs are installed

```bash
microk8s kubectl get crd | grep opensandbox
```

Expected output:
```
batchsandboxes.sandbox.opensandbox.io   2024-xx-xx
pools.sandbox.opensandbox.io            2024-xx-xx
```

---

## Step 4: Deploy the Controller

### 4.1 Create the opensandbox-system Namespace

```bash
microk8s kubectl create namespace opensandbox-system --dry-run=client -o yaml | microk8s kubectl apply -f -
```

### 4.2 Deploy Controller

```bash
cd kubernetes

make deploy \
  IMG=localhost:32000/opensandbox-controller:latest \
  TASK_EXECUTOR_IMG=localhost:32000/opensandbox-task-executor:latest \
  KUBECTL="microk8s kubectl"
```

### 4.3 Verify Controller is Running

```bash
microk8s kubectl get pods -n opensandbox-system
```

Expected output:
```
NAME                                           READY   STATUS    RESTARTS   AGE
opensandbox-controller-manager-xxxxx-xxxxx     1/1     Running   0          30s
```

Check controller logs:
```bash
microk8s kubectl logs -n opensandbox-system -l control-plane=controller-manager -f
```

---

## Step 5: Create a Pool

A Pool pre-warms sandbox pods for fast allocation.

### 5.1 Create the opensandbox Namespace

```bash
microk8s kubectl create namespace opensandbox
```

### 5.2 Create a Simple Pool (using nginx for testing)

Create `pool-simple.yaml`:

```yaml
apiVersion: sandbox.opensandbox.io/v1alpha1
kind: Pool
metadata:
  name: simple-pool
  namespace: opensandbox
spec:
  template:
    metadata:
      labels:
        app: sandbox
    spec:
      containers:
        - name: sandbox
          image: nginx:alpine
          ports:
            - containerPort: 80
  capacitySpec:
    bufferMin: 1
    bufferMax: 3
    poolMin: 1
    poolMax: 5
```

Apply it:
```bash
microk8s kubectl apply -f pool-simple.yaml
```

### 5.3 Create a Full Pool (with execd and task-executor)

Create `pool-full.yaml`:

```yaml
apiVersion: sandbox.opensandbox.io/v1alpha1
kind: Pool
metadata:
  name: code-interpreter-pool
  namespace: opensandbox
spec:
  template:
    metadata:
      labels:
        app: code-interpreter
    spec:
      volumes:
        - name: sandbox-storage
          emptyDir: {}
        - name: opensandbox-bin
          emptyDir: {}
      initContainers:
        - name: task-executor-installer
          image: localhost:32000/opensandbox-task-executor:latest
          command: ["/bin/sh", "-c"]
          args:
            - |
              cp /workspace/server /opt/opensandbox/bin/task-executor &&
              chmod +x /opt/opensandbox/bin/task-executor
          volumeMounts:
            - name: opensandbox-bin
              mountPath: /opt/opensandbox/bin
        - name: execd-installer
          image: localhost:32000/opensandbox-execd:latest
          command: ["/bin/sh", "-c"]
          args:
            - |
              cp ./execd /opt/opensandbox/bin/execd &&
              cp ./bootstrap.sh /opt/opensandbox/bin/bootstrap.sh &&
              chmod +x /opt/opensandbox/bin/execd &&
              chmod +x /opt/opensandbox/bin/bootstrap.sh
          volumeMounts:
            - name: opensandbox-bin
              mountPath: /opt/opensandbox/bin
      containers:
        - name: sandbox
          image: localhost:32000/code-interpreter:latest  # or use python:3.11 for testing
          command:
            - "/bin/sh"
            - "-c"
            - |
              /opt/opensandbox/bin/task-executor -listen-addr=0.0.0.0:5758 >/tmp/task-executor.log 2>&1
          env:
            - name: SANDBOX_MAIN_CONTAINER
              value: main
            - name: EXECD_ENVS
              value: /opt/opensandbox/.env
            - name: EXECD
              value: /opt/opensandbox/bin/execd
          volumeMounts:
            - name: sandbox-storage
              mountPath: /var/lib/sandbox
            - name: opensandbox-bin
              mountPath: /opt/opensandbox/bin
          resources:
            requests:
              memory: "256Mi"
              cpu: "100m"
            limits:
              memory: "1Gi"
              cpu: "500m"
  capacitySpec:
    bufferMin: 1
    bufferMax: 3
    poolMin: 1
    poolMax: 10
```

Apply it:
```bash
microk8s kubectl apply -f pool-full.yaml
```

### 5.4 Verify Pool Status

```bash
microk8s kubectl get pool -n opensandbox

# Check pool details
microk8s kubectl describe pool simple-pool -n opensandbox
```

---

## Step 6: Create Sandboxes

### 6.1 Create a BatchSandbox

Create `batchsandbox.yaml`:

```yaml
apiVersion: sandbox.opensandbox.io/v1alpha1
kind: BatchSandbox
metadata:
  name: my-sandbox
  namespace: opensandbox
spec:
  replicas: 2
  poolRef: simple-pool
  expireTime: "2026-12-31T23:59:59Z"
```

Apply it:
```bash
microk8s kubectl apply -f batchsandbox.yaml
```

### 6.2 Verify Sandbox Pods

```bash
# Check BatchSandbox status
microk8s kubectl get batchsandbox -n opensandbox

# Check pods created
microk8s kubectl get pods -n opensandbox

# Get detailed status
microk8s kubectl describe batchsandbox my-sandbox -n opensandbox
```

---

## Step 7: Testing with Code Interpreter Example

This section shows how to test your MicroK8s deployment using the existing `examples/code-interpreter` example from the project.

### 7.1 Prerequisites for Example

Install the Python SDK and server:

```bash
# Install OpenSandbox packages
pip install opensandbox opensandbox-code-interpreter opensandbox-server
```

### 7.2 Create the Pool for Code Interpreter

First, ensure you have the code-interpreter pool deployed. The `pool-sample.yaml` is configured to work directly with the `examples/code-interpreter/main_use_pool.py` example:

```bash
# Apply the pool-sample (named "pool-sample" to match the example code)
microk8s kubectl apply -f docs/microk8s/pool-sample.yaml
```

Alternatively, use your own pool configuration:

```bash
# Apply the full pool with a different name
microk8s kubectl apply -f docs/microk8s/pool-full.yaml
```

> **Note:** If using `pool-full.yaml`, update the `poolRef` in the example code or create a BatchSandbox manually.

Verify the pool is ready:

```bash
microk8s kubectl get pool -n opensandbox
microk8s kubectl get pods -n opensandbox
```

### 7.3 Configure and Start the OpenSandbox Server

Use the pre-configured MicroK8s server config from this repository:

```bash
# From project root directory
SANDBOX_CONFIG_PATH=docs/microk8s/server-config.toml opensandbox-server
```

Or create your own configuration:

```bash
# Create config directory
mkdir -p ~/.config/opensandbox

# Create the server configuration
cat > ~/.config/opensandbox/config.toml << 'EOF'
[server]
host = "0.0.0.0"
port = 8080
log_level = "INFO"
# api_key = "your-secret-key"  # Uncomment for production

[runtime]
type = "kubernetes"
execd_image = "localhost:32000/opensandbox-execd:latest"

[storage]
allowed_host_paths = []

[kubernetes]
# Use MicroK8s kubeconfig
kubeconfig_path = "/var/snap/microk8s/current/credentials/client.config"
namespace = "opensandbox"
workload_provider = "batchsandbox"
batchsandbox_template_file = "~/.config/opensandbox/batchsandbox-template.yaml"
EOF

# Create the BatchSandbox template
cat > ~/.config/opensandbox/batchsandbox-template.yaml << 'EOF'
metadata:
spec:
  replicas: 1
  template:
    spec:
      restartPolicy: Never
      tolerations:
        - operator: "Exists"
EOF

# Start the server
SANDBOX_CONFIG_PATH=~/.config/opensandbox/config.toml opensandbox-server
```

Verify server is running:

```bash
curl http://localhost:8080/health
```

### 7.4 Run the Code Interpreter Example

In a new terminal, run the example:

```bash
cd examples/code-interpreter

# Set environment variables
export SANDBOX_DOMAIN="localhost:8080"
export SANDBOX_IMAGE="localhost:32000/code-interpreter:latest"
# export SANDBOX_API_KEY="your-secret-key"  # If API key is configured

# Run the basic example
python main.py
```

Expected output:

```text
=== Python example ===
[Python stdout] Hello from Python!
[Python result] {'py': '3.14.2', 'sum': 4}

=== Java example ===
[Java stdout] Hello from Java!
[Java stdout] 2 + 3 = 5
[Java result] 5

=== Go example ===
[Go stdout] Hello from Go!
3 + 4 = 7

=== TypeScript example ===
[TypeScript stdout] Hello from TypeScript!
[TypeScript stdout] sum = 6
```

### 7.5 Run the Pool-Based Example

The `main_use_pool.py` example uses a pre-created pool for faster sandbox allocation:

```bash
cd examples/code-interpreter

# Ensure pool-sample exists (or update poolRef in the code to match your pool name)
export SANDBOX_DOMAIN="localhost:8080"
export SANDBOX_IMAGE="localhost:32000/code-interpreter:latest"

# Run the pool-based example
python main_use_pool.py
```

### 7.6 Watch Sandbox Creation in Kubernetes

While running the examples, watch the sandbox resources being created:

```bash
# In a separate terminal, watch BatchSandbox resources
microk8s kubectl get batchsandbox -n opensandbox -w

# Watch pods
microk8s kubectl get pods -n opensandbox -w
```

---

## Step 8: Manual Testing

### 8.1 Test Basic Connectivity

```bash
# Get sandbox pod name
POD_NAME=$(microk8s kubectl get pods -n opensandbox -l app=sandbox -o jsonpath='{.items[0].metadata.name}')

# Port forward to access the sandbox
microk8s kubectl port-forward -n opensandbox $POD_NAME 8080:80
```

In another terminal:
```bash
curl http://localhost:8080
```

### 8.2 Test execd (if using full pool)

```bash
# Port forward to execd port
POD_NAME=$(microk8s kubectl get pods -n opensandbox -l app=code-interpreter -o jsonpath='{.items[0].metadata.name}')
microk8s kubectl port-forward -n opensandbox $POD_NAME 44772:44772
```

Test execd health:
```bash
curl http://localhost:44772/ping
```

Execute code:
```bash
curl -X POST http://localhost:44772/code \
  -H "Content-Type: application/json" \
  -d '{
    "language": "python",
    "code": "print(\"Hello from OpenSandbox!\")"
  }'
```

### 8.3 Scale Test

```bash
# Scale up sandboxes
microk8s kubectl patch batchsandbox my-sandbox -n opensandbox \
  --type='json' -p='[{"op": "replace", "path": "/spec/replicas", "value": 5}]'

# Watch pods scale
microk8s kubectl get pods -n opensandbox -w
```

### 8.4 Pool Metrics

```bash
# Check pool status
microk8s kubectl get pool -n opensandbox -o yaml
```

---

## Troubleshooting

### Controller not starting

```bash
# Check controller logs
microk8s kubectl logs -n opensandbox-system -l control-plane=controller-manager --tail=100

# Check events
microk8s kubectl get events -n opensandbox-system --sort-by='.lastTimestamp'
```

### Pods stuck in Pending

```bash
# Check pod events
microk8s kubectl describe pod <pod-name> -n opensandbox

# Check node resources
microk8s kubectl describe nodes
```

### Image pull errors

```bash
# Verify image exists in registry
curl -s http://localhost:32000/v2/opensandbox-controller/tags/list

# Check if registry is accessible from within cluster
microk8s kubectl run test-registry --rm -it --image=busybox --restart=Never -- \
  wget -qO- http://localhost:32000/v2/_catalog
```

### Registry not accessible

```bash
# Check registry pod
microk8s kubectl get pods -n container-registry

# Restart registry if needed
microk8s disable registry && microk8s enable registry
```

### CRD not found

```bash
# Reinstall CRDs
cd kubernetes
make install KUBECTL="microk8s kubectl"

# Verify
microk8s kubectl api-resources | grep opensandbox
```

---

## Cleanup

### Remove Sandboxes and Pools

```bash
microk8s kubectl delete batchsandbox --all -n opensandbox
microk8s kubectl delete pool --all -n opensandbox
microk8s kubectl delete namespace opensandbox
```

### Undeploy Controller

```bash
cd kubernetes
make undeploy KUBECTL="microk8s kubectl"
```

### Uninstall CRDs

```bash
cd kubernetes
make uninstall KUBECTL="microk8s kubectl"
```

### Remove Images from Registry

```bash
# Images in microk8s registry are stored in /var/snap/microk8s/common/default-storage
# To clean up, you can disable and re-enable the registry
microk8s disable registry
microk8s enable registry
```

---

## Advanced Configuration

### Resource Limits

Adjust pool resource limits for your environment:

```yaml
containers:
  - name: sandbox
    resources:
      requests:
        memory: "512Mi"
        cpu: "250m"
      limits:
        memory: "2Gi"
        cpu: "1000m"
```

### Persistent Storage

Add PVC for persistent data:

```yaml
spec:
  template:
    spec:
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: sandbox-data-pvc
```

### Network Policies

Enable network isolation:

```bash
microk8s enable network
```

---

## Next Steps

- Set up the [Ingress component](../components/ingress/README.md) for external access
- Configure [Egress policies](../components/egress/README.md) for network isolation
- Deploy the [Server component](../server/README.md) for REST API access
- Check [examples](../examples/) for integration patterns

---

## Quick Reference

| Command | Description |
|---------|-------------|
| `microk8s kubectl get pool -n opensandbox` | List pools |
| `microk8s kubectl get batchsandbox -n opensandbox` | List sandboxes |
| `microk8s kubectl get pods -n opensandbox` | List sandbox pods |
| `microk8s kubectl logs -n opensandbox-system -l control-plane=controller-manager` | Controller logs |
| `microk8s kubectl describe pool <name> -n opensandbox` | Pool details |
| `curl http://localhost:32000/v2/_catalog` | List registry images |
