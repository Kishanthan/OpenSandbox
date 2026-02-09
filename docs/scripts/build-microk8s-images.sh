#!/bin/bash
# Build all OpenSandbox images and push to MicroK8s registry
#
# Usage: ./build-microk8s-images.sh [--skip-code-interpreter]
#
# Prerequisites:
#   - MicroK8s with registry enabled: microk8s enable registry
#   - Docker configured with insecure registry localhost:32000

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

REGISTRY="${REGISTRY:-localhost:32000}"
TAG="${TAG:-latest}"
SKIP_CODE_INTERPRETER=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --skip-code-interpreter)
            SKIP_CODE_INTERPRETER=true
            shift
            ;;
        --registry=*)
            REGISTRY="${arg#*=}"
            shift
            ;;
        --tag=*)
            TAG="${arg#*=}"
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --skip-code-interpreter  Skip building the large code-interpreter image"
            echo "  --registry=<url>         Registry URL (default: localhost:32000)"
            echo "  --tag=<tag>              Image tag (default: latest)"
            echo "  --help                   Show this help message"
            exit 0
            ;;
    esac
done

echo "=============================================="
echo "OpenSandbox MicroK8s Image Builder"
echo "=============================================="
echo "Registry: ${REGISTRY}"
echo "Tag: ${TAG}"
echo "Skip Code Interpreter: ${SKIP_CODE_INTERPRETER}"
echo "=============================================="

# Check prerequisites
echo ""
echo "[1/6] Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed"
    exit 1
fi

if ! curl -s "http://${REGISTRY}/v2/_catalog" &> /dev/null; then
    echo "WARNING: Cannot reach registry at ${REGISTRY}"
    echo "Make sure MicroK8s registry is enabled: microk8s enable registry"
    echo "And Docker is configured with insecure registry"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Build Controller
echo ""
echo "[2/6] Building Controller image..."
cd "${PROJECT_ROOT}/kubernetes"
make docker-build IMG="${REGISTRY}/opensandbox-controller:${TAG}"
echo "Pushing opensandbox-controller..."
docker push "${REGISTRY}/opensandbox-controller:${TAG}"

# Build Task Executor
echo ""
echo "[3/6] Building Task Executor image..."
cd "${PROJECT_ROOT}/kubernetes"
make docker-build-task-executor TASK_EXECUTOR_IMG="${REGISTRY}/opensandbox-task-executor:${TAG}"
echo "Pushing opensandbox-task-executor..."
docker push "${REGISTRY}/opensandbox-task-executor:${TAG}"

# Build execd
echo ""
echo "[4/6] Building execd image..."
cd "${PROJECT_ROOT}/components/execd"
docker build -t "${REGISTRY}/opensandbox-execd:${TAG}" .
echo "Pushing opensandbox-execd..."
docker push "${REGISTRY}/opensandbox-execd:${TAG}"

# Build Ingress (optional)
echo ""
echo "[5/6] Building Ingress image..."
if [ -f "${PROJECT_ROOT}/components/ingress/Dockerfile" ]; then
    cd "${PROJECT_ROOT}/components/ingress"
    docker build -t "${REGISTRY}/opensandbox-ingress:${TAG}" .
    echo "Pushing opensandbox-ingress..."
    docker push "${REGISTRY}/opensandbox-ingress:${TAG}"
else
    echo "Skipping ingress (Dockerfile not found)"
fi

# Build Code Interpreter (optional, large image)
echo ""
echo "[6/6] Building Code Interpreter image..."
if [ "$SKIP_CODE_INTERPRETER" = true ]; then
    echo "Skipping code-interpreter (--skip-code-interpreter flag set)"
else
    if [ -f "${PROJECT_ROOT}/sandboxes/code-interpreter/Dockerfile" ]; then
        echo "WARNING: This image is large (~5GB) and takes a long time to build."
        read -p "Build code-interpreter image? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cd "${PROJECT_ROOT}/sandboxes/code-interpreter"
            docker build -t "${REGISTRY}/code-interpreter:${TAG}" .
            echo "Pushing code-interpreter..."
            docker push "${REGISTRY}/code-interpreter:${TAG}"
        else
            echo "Skipping code-interpreter"
        fi
    else
        echo "Skipping code-interpreter (Dockerfile not found)"
    fi
fi

# Summary
echo ""
echo "=============================================="
echo "Build Complete!"
echo "=============================================="
echo ""
echo "Images pushed to ${REGISTRY}:"
curl -s "http://${REGISTRY}/v2/_catalog" 2>/dev/null | grep -o '"[^"]*"' | tr -d '"' | while read repo; do
    echo "  - ${REGISTRY}/${repo}:${TAG}"
done

echo ""
echo "Next steps:"
echo "  1. Install CRDs:"
echo "     cd kubernetes && make install KUBECTL='microk8s kubectl'"
echo ""
echo "  2. Deploy controller:"
echo "     make deploy IMG=${REGISTRY}/opensandbox-controller:${TAG} \\"
echo "                 TASK_EXECUTOR_IMG=${REGISTRY}/opensandbox-task-executor:${TAG} \\"
echo "                 KUBECTL='microk8s kubectl'"
echo ""
echo "  3. Create namespace and apply samples:"
echo "     microk8s kubectl create namespace opensandbox"
echo "     microk8s kubectl apply -f docs/microk8s/"
