#!/bin/bash
# Test OpenSandbox deployment on MicroK8s
#
# Usage: ./test-microk8s-deployment.sh

set -e

KUBECTL="microk8s kubectl"
NAMESPACE="opensandbox"

echo "=============================================="
echo "OpenSandbox MicroK8s Deployment Test"
echo "=============================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}[PASS]${NC} $1"; }
fail() { echo -e "${RED}[FAIL]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
info() { echo -e "[INFO] $1"; }

# Test 1: Check MicroK8s status
echo ""
echo "Test 1: MicroK8s Status"
echo "----------------------------------------"
if microk8s status --wait-ready &> /dev/null; then
    pass "MicroK8s is running"
else
    fail "MicroK8s is not running"
    exit 1
fi

# Test 2: Check required addons
echo ""
echo "Test 2: Required Addons"
echo "----------------------------------------"
REQUIRED_ADDONS=("dns" "storage" "registry")
for addon in "${REQUIRED_ADDONS[@]}"; do
    if microk8s status | grep -q "${addon}: enabled"; then
        pass "Addon '${addon}' is enabled"
    else
        fail "Addon '${addon}' is not enabled"
        echo "  Run: microk8s enable ${addon}"
    fi
done

# Test 3: Check CRDs
echo ""
echo "Test 3: Custom Resource Definitions"
echo "----------------------------------------"
if $KUBECTL get crd batchsandboxes.sandbox.opensandbox.io &> /dev/null; then
    pass "BatchSandbox CRD is installed"
else
    fail "BatchSandbox CRD is not installed"
fi

if $KUBECTL get crd pools.sandbox.opensandbox.io &> /dev/null; then
    pass "Pool CRD is installed"
else
    fail "Pool CRD is not installed"
fi

# Test 4: Check controller
echo ""
echo "Test 4: Controller Status"
echo "----------------------------------------"
CONTROLLER_POD=$($KUBECTL get pods -n opensandbox-system -l control-plane=controller-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$CONTROLLER_POD" ]; then
    STATUS=$($KUBECTL get pod -n opensandbox-system $CONTROLLER_POD -o jsonpath='{.status.phase}')
    if [ "$STATUS" = "Running" ]; then
        pass "Controller is running ($CONTROLLER_POD)"
    else
        fail "Controller status: $STATUS"
    fi
else
    fail "Controller pod not found"
    echo "  Deploy with: make deploy IMG=... KUBECTL='microk8s kubectl'"
fi

# Test 5: Check namespace
echo ""
echo "Test 5: Namespace"
echo "----------------------------------------"
if $KUBECTL get namespace $NAMESPACE &> /dev/null; then
    pass "Namespace '$NAMESPACE' exists"
else
    warn "Namespace '$NAMESPACE' does not exist"
    echo "  Create with: $KUBECTL create namespace $NAMESPACE"
fi

# Test 6: Check Pools
echo ""
echo "Test 6: Pools"
echo "----------------------------------------"
POOLS=$($KUBECTL get pool -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "$POOLS" ]; then
    pass "Found pools: $POOLS"
    for pool in $POOLS; do
        READY=$($KUBECTL get pool -n $NAMESPACE $pool -o jsonpath='{.status.availableReplicas}' 2>/dev/null || echo "0")
        info "  Pool '$pool' has $READY available replicas"
    done
else
    warn "No pools found in namespace '$NAMESPACE'"
fi

# Test 7: Check BatchSandboxes
echo ""
echo "Test 7: BatchSandboxes"
echo "----------------------------------------"
SANDBOXES=$($KUBECTL get batchsandbox -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "$SANDBOXES" ]; then
    pass "Found sandboxes: $SANDBOXES"
    for sb in $SANDBOXES; do
        READY=$($KUBECTL get batchsandbox -n $NAMESPACE $sb -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        DESIRED=$($KUBECTL get batchsandbox -n $NAMESPACE $sb -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "?")
        info "  BatchSandbox '$sb': $READY/$DESIRED ready"
    done
else
    warn "No batchsandboxes found in namespace '$NAMESPACE'"
fi

# Test 8: Check Pods
echo ""
echo "Test 8: Sandbox Pods"
echo "----------------------------------------"
PODS=$($KUBECTL get pods -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")
if [ -n "$PODS" ]; then
    RUNNING_COUNT=$($KUBECTL get pods -n $NAMESPACE --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)
    TOTAL_COUNT=$($KUBECTL get pods -n $NAMESPACE -o name 2>/dev/null | wc -l)
    pass "Found $RUNNING_COUNT/$TOTAL_COUNT pods running"
    $KUBECTL get pods -n $NAMESPACE --no-headers 2>/dev/null | while read line; do
        info "  $line"
    done
else
    warn "No pods found in namespace '$NAMESPACE'"
fi

# Test 9: Registry check
echo ""
echo "Test 9: Registry Images"
echo "----------------------------------------"
if curl -s http://localhost:32000/v2/_catalog &> /dev/null; then
    pass "Registry is accessible"
    REPOS=$(curl -s http://localhost:32000/v2/_catalog | grep -o '"[^"]*"' | tr -d '"' | tr '\n' ' ')
    info "  Available images: $REPOS"
else
    warn "Registry is not accessible at localhost:32000"
fi

# Summary
echo ""
echo "=============================================="
echo "Test Summary"
echo "=============================================="
echo ""
echo "To create a basic test deployment:"
echo "  $KUBECTL create namespace $NAMESPACE"
echo "  $KUBECTL apply -f docs/microk8s/pool.yaml"
echo "  $KUBECTL apply -f docs/microk8s/batchsandbox.yaml"
echo ""
echo "To watch pods:"
echo "  $KUBECTL get pods -n $NAMESPACE -w"
echo ""
echo "To check controller logs:"
echo "  $KUBECTL logs -n opensandbox-system -l control-plane=controller-manager -f"
