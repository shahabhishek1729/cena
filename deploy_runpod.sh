#!/usr/bin/env bash
#
# Deploy DiffusionGuard server to a RunPod GPU pod
# ==================================================
# Prerequisites:
#   1. Create a pod on runpod.io with:
#      - Template: RunPod PyTorch 2.x  (or any CUDA image)
#      - GPU: Any NVIDIA GPU (A100, A40, RTX 4090, etc.)
#      - Expose TCP port 8888
#   2. Get your pod's SSH connection string from the RunPod dashboard
#
# Usage:
#   ./deploy_runpod.sh <ssh-connection>
#   ./deploy_runpod.sh root@ssh.runpod.io -p 12345           # SSH with custom port
#   ./deploy_runpod.sh "ssh -p 12345 root@ssh.runpod.io"     # Full SSH command
#
# After deploy, the server URL will be:
#   https://<POD_ID>-8888.proxy.runpod.net
#
set -euo pipefail

if [ $# -lt 1 ]; then
    cat <<'USAGE'
Usage: ./deploy_runpod.sh <ssh-args>

Examples:
  # Standard RunPod SSH (check dashboard for your port)
  ./deploy_runpod.sh -p 22177 root@100.67.2.3

  # Using the RunPod SSH proxy
  ./deploy_runpod.sh -p 22177 root@ssh.runpod.io

After deploying:
  1. Note your pod ID from the RunPod dashboard
  2. Update backends.json with the pod_id
  3. Or set:  export RUNPOD_POD_ID=<your-pod-id>
  4. Run:    python client/glaze.py --image photo.png --mask mask.png --backend runpod
USAGE
    exit 1
fi

SSH_ARGS="$@"
REMOTE_DIR="/workspace/diffusionguard_project"

echo "=== Deploying DiffusionGuard to RunPod ==="
echo "SSH args: $SSH_ARGS"
echo ""

# 1. Create remote directory structure
echo "[1/5] Creating remote directories..."
ssh $SSH_ARGS "mkdir -p $REMOTE_DIR/server"

# 2. Copy server code
echo "[2/5] Copying server code..."
scp ${SSH_ARGS/root@/-o User=root } server/app.py server/requirements.txt "$REMOTE_DIR/server/" 2>/dev/null || \
    ssh $SSH_ARGS "cat > $REMOTE_DIR/server/app.py" < server/app.py && \
    ssh $SSH_ARGS "cat > $REMOTE_DIR/server/requirements.txt" < server/requirements.txt

# Try scp first, fall back to ssh cat for non-standard SSH configs
echo "[2/5] Copying server code (using ssh pipe)..."
ssh $SSH_ARGS "mkdir -p $REMOTE_DIR/server"
cat server/app.py | ssh $SSH_ARGS "cat > $REMOTE_DIR/server/app.py"
cat server/requirements.txt | ssh $SSH_ARGS "cat > $REMOTE_DIR/server/requirements.txt"

# 3. Clone DiffusionGuard repo
echo "[3/5] Cloning DiffusionGuard repo..."
ssh $SSH_ARGS "cd $REMOTE_DIR && [ -d DiffusionGuard ] || git clone https://github.com/choi403/DiffusionGuard.git"

# 4. Install dependencies
echo "[4/5] Installing Python dependencies..."
ssh $SSH_ARGS "cd $REMOTE_DIR && pip install -q diffusers==0.24.0 transformers datasets huggingface-hub numpy omegaconf opencv-contrib-python scikit-learn tqdm hydra-core flask pillow"

# 5. Start the server
echo "[5/5] Starting the server..."
echo ""
echo "Starting server in background. It will download the SD Inpainting model on first run (~4GB)."
echo ""
ssh $SSH_ARGS "cd $REMOTE_DIR/server && nohup python app.py > /workspace/diffguard_server.log 2>&1 &"

echo "=== Deploy complete! ==="
echo ""
echo "The server is starting up at port 8888."
echo ""
echo "Access via RunPod proxy:"
echo "  https://<POD_ID>-8888.proxy.runpod.net/health"
echo ""
echo "To check logs:"
echo "  ssh $SSH_ARGS 'tail -f /workspace/diffguard_server.log'"
echo ""
echo "Next steps:"
echo "  1. Get your pod ID from the RunPod dashboard"
echo "  2. export RUNPOD_POD_ID=<your-pod-id>"
echo "  3. python client/glaze.py --image photo.png --mask mask.png --backend runpod"
