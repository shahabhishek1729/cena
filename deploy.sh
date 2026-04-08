#!/usr/bin/env bash
#
# Deploy DiffusionGuard server to a GPU backend
# ===============================================
#
# Usage:
#   ./deploy.sh gx10   <user>@<host>             Deploy to ASUS Ascent GX10
#   ./deploy.sh runpod  <ssh-args>                Deploy to RunPod GPU pod
#   ./deploy.sh ssh     <user>@<host>             Deploy to any SSH-accessible GPU box
#
# Examples:
#   ./deploy.sh gx10   nikhil@spark-abcd.local
#   ./deploy.sh runpod  -p 22177 root@ssh.runpod.io
#   ./deploy.sh ssh     ubuntu@my-gpu-server.com
#
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: ./deploy.sh <target-type> <connection-args...>

Target types:
  gx10    ASUS Ascent GX10 (uses Docker container 'diffguard')
  runpod  RunPod GPU pod (direct install, no Docker)
  ssh     Any SSH-accessible machine with NVIDIA GPU (direct install)

Examples:
  ./deploy.sh gx10   nikhil@spark-abcd.local
  ./deploy.sh runpod  -p 22177 root@ssh.runpod.io
  ./deploy.sh ssh     ubuntu@lambda-box.com
EOF
    exit 1
}

[ $# -lt 2 ] && usage

TARGET_TYPE="$1"
shift
SSH_ARGS="$@"
REMOTE_DIR="diffusionguard_project"
PIP_DEPS="diffusers==0.24.0 transformers datasets huggingface-hub numpy omegaconf opencv-contrib-python scikit-learn tqdm hydra-core flask pillow"

# -----------------------------------------------------------------------
# Helper: copy server code via SSH pipe (works with any SSH config)
# -----------------------------------------------------------------------
copy_server_code() {
    local ssh_args="$1"
    local remote_dir="$2"
    echo "[*] Copying server code..."
    ssh $ssh_args "mkdir -p $remote_dir/server"
    cat server/app.py          | ssh $ssh_args "cat > $remote_dir/server/app.py"
    cat server/requirements.txt | ssh $ssh_args "cat > $remote_dir/server/requirements.txt"
}

clone_diffguard() {
    local ssh_args="$1"
    local remote_dir="$2"
    echo "[*] Cloning DiffusionGuard repo (if needed)..."
    ssh $ssh_args "cd $remote_dir && [ -d DiffusionGuard ] || git clone https://github.com/choi403/DiffusionGuard.git"
}

# -----------------------------------------------------------------------
# GX10 deploy (Docker-based)
# -----------------------------------------------------------------------
deploy_gx10() {
    local remote="$REMOTE_DIR"
    echo "=== Deploying to GX10 ($SSH_ARGS) ==="

    copy_server_code "$SSH_ARGS" "~/$remote"
    clone_diffguard  "$SSH_ARGS" "~/$remote"

    echo "[*] Checking Docker container 'diffguard'..."
    ssh $SSH_ARGS "docker ps -a --format '{{.Names}}' | grep -q diffguard" || {
        echo "ERROR: Docker container 'diffguard' not found."
        echo "Create it first — see SETUP_GX10.md Phase 3."
        exit 1
    }

    echo "[*] Installing dependencies inside Docker container..."
    ssh $SSH_ARGS "docker start diffguard 2>/dev/null; docker exec diffguard pip install -q $PIP_DEPS"

    echo ""
    echo "=== GX10 deploy complete! ==="
    echo ""
    echo "Start the server:"
    echo "  ssh $SSH_ARGS"
    echo "  docker exec -it diffguard bash -c 'cd /workspace/project/server && python app.py'"
    echo ""
    echo "Then from your laptop:"
    echo "  python client/glaze.py --image photo.png --mask mask.png --backend gx10"
}

# -----------------------------------------------------------------------
# RunPod deploy (direct install, no Docker)
# -----------------------------------------------------------------------
deploy_runpod() {
    local remote="/workspace/$REMOTE_DIR"
    echo "=== Deploying to RunPod ($SSH_ARGS) ==="

    copy_server_code "$SSH_ARGS" "$remote"
    clone_diffguard  "$SSH_ARGS" "$remote"

    echo "[*] Installing dependencies..."
    ssh $SSH_ARGS "pip install -q $PIP_DEPS"

    echo "[*] Starting server in background..."
    ssh $SSH_ARGS "cd $remote/server && nohup python app.py > /workspace/diffguard.log 2>&1 &"

    echo ""
    echo "=== RunPod deploy complete! ==="
    echo ""
    echo "Server is starting on port 8888."
    echo "First run downloads the model (~4GB) — check logs:"
    echo "  ssh $SSH_ARGS 'tail -f /workspace/diffguard.log'"
    echo ""
    echo "Access URL: https://<POD_ID>-8888.proxy.runpod.net"
    echo ""
    echo "  1. Get your pod ID from runpod.io dashboard"
    echo "  2. export RUNPOD_POD_ID=<pod-id>"
    echo "  3. python client/glaze.py --image photo.png --mask mask.png --backend runpod"
}

# -----------------------------------------------------------------------
# Generic SSH deploy (any machine with GPU)
# -----------------------------------------------------------------------
deploy_ssh() {
    local remote="~/$REMOTE_DIR"
    echo "=== Deploying to remote GPU ($SSH_ARGS) ==="

    copy_server_code "$SSH_ARGS" "$remote"
    clone_diffguard  "$SSH_ARGS" "$remote"

    echo "[*] Installing dependencies..."
    ssh $SSH_ARGS "pip install -q $PIP_DEPS"

    echo ""
    echo "=== SSH deploy complete! ==="
    echo ""
    echo "Start the server:"
    echo "  ssh $SSH_ARGS 'cd ~/$REMOTE_DIR/server && python app.py'"
    echo ""
    echo "Then from your laptop:"
    echo "  python client/glaze.py --image photo.png --mask mask.png --server http://<host>:8888"
}

# -----------------------------------------------------------------------
# Dispatch
# -----------------------------------------------------------------------
case "$TARGET_TYPE" in
    gx10)   deploy_gx10   ;;
    runpod) deploy_runpod  ;;
    ssh)    deploy_ssh     ;;
    *)
        echo "ERROR: Unknown target type '$TARGET_TYPE'"
        usage
        ;;
esac
