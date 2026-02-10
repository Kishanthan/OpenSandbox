#!/bin/bash
# Run the code-interpreter example against MicroK8s deployment
#
# Usage: ./run-code-interpreter-example.sh [--use-pool]
#
# Prerequisites:
#   1. MicroK8s cluster running with OpenSandbox deployed
#   2. Pool created (for --use-pool option)
#   3. Python packages: pip install opensandbox opensandbox-code-interpreter

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

USE_POOL=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --use-pool)
            USE_POOL=true
            shift
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --use-pool    Run the pool-based example (main_use_pool.py)"
            echo "  --help        Show this help message"
            echo ""
            echo "Environment variables:"
            echo "  SANDBOX_DOMAIN    Server address (default: localhost:8080)"
            echo "  SANDBOX_API_KEY   API key if authentication is enabled"
            echo "  SANDBOX_IMAGE     Sandbox image to use"
            exit 0
            ;;
    esac
done

echo "=============================================="
echo "OpenSandbox Code Interpreter Example"
echo "=============================================="

# Check if server is running
SANDBOX_DOMAIN="${SANDBOX_DOMAIN:-localhost:8080}"
echo "Checking server at ${SANDBOX_DOMAIN}..."

if ! curl -s "http://${SANDBOX_DOMAIN}/health" > /dev/null 2>&1; then
    echo ""
    echo "ERROR: OpenSandbox server is not running at ${SANDBOX_DOMAIN}"
    echo ""
    echo "Start the server first:"
    echo "  SANDBOX_CONFIG_PATH=docs/microk8s/server-config.toml opensandbox-server"
    echo ""
    exit 1
fi

echo "Server is running!"

# Check Python packages
echo ""
echo "Checking Python packages..."
if ! python -c "import opensandbox" 2>/dev/null; then
    echo "Installing opensandbox..."
    pip install opensandbox opensandbox-code-interpreter
fi

# Set environment variables
export SANDBOX_DOMAIN="${SANDBOX_DOMAIN}"
export SANDBOX_IMAGE="${SANDBOX_IMAGE:-localhost:32000/code-interpreter:latest}"

echo ""
echo "Configuration:"
echo "  SANDBOX_DOMAIN: ${SANDBOX_DOMAIN}"
echo "  SANDBOX_IMAGE: ${SANDBOX_IMAGE}"
if [ -n "${SANDBOX_API_KEY}" ]; then
    echo "  SANDBOX_API_KEY: (set)"
fi

# Run the example
cd "${PROJECT_ROOT}/examples/code-interpreter"

echo ""
echo "=============================================="
if [ "$USE_POOL" = true ]; then
    echo "Running pool-based example (main_use_pool.py)..."
    echo "=============================================="
    echo ""

    # Check if pool exists
    if ! microk8s kubectl get pool pool-sample -n opensandbox > /dev/null 2>&1; then
        echo "WARNING: Pool 'pool-sample' not found!"
        echo "Create it with: microk8s kubectl apply -f docs/microk8s/pool-sample.yaml"
        echo ""
        read -p "Continue anyway? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    python main_use_pool.py
else
    echo "Running basic example (main.py)..."
    echo "=============================================="
    echo ""
    python main.py
fi

echo ""
echo "=============================================="
echo "Example completed successfully!"
echo "=============================================="
