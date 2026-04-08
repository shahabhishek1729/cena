# RunPod Setup — DiffusionGuard Server

## Do I Need to Request Anything on HuggingFace?

**No.** The model `runwayml/stable-diffusion-inpainting` is fully public. No gated access,
no tokens, no approval. It downloads automatically on first run (~4GB).

If you want to skip the download wait on the pod, you can optionally set a HuggingFace
token to get faster CDN speeds, but it's not required:
```bash
# Optional — only if you have an HF account and want faster downloads
export HF_TOKEN=hf_xxxxx
```

---

## Step-by-Step RunPod Setup

### Step 1: Create a RunPod Account

1. Go to [runpod.io](https://www.runpod.io) and sign up.
2. Add credits ($5-10 is plenty for testing).

### Step 2: Add Your SSH Key

You need this to SSH into your pod and deploy code.

```bash
# On your laptop — check if you already have a key
cat ~/.ssh/id_ed25519.pub

# If that file doesn't exist, generate one:
ssh-keygen -t ed25519 -C "your-email@example.com"
cat ~/.ssh/id_ed25519.pub
```

Copy the entire output (starts with `ssh-ed25519 ...`), then:

1. Go to [RunPod Settings](https://www.runpod.io/console/user/settings)
2. Find **SSH Public Keys**
3. Paste your key and save

### Step 3: Create a GPU Pod

1. Go to [RunPod Pods](https://www.runpod.io/console/pods)
2. Click **+ Deploy**
3. Configure:

| Setting | Value |
|---------|-------|
| **GPU** | Any NVIDIA GPU works. Recommended: **RTX A4000** ($0.20/hr) or **RTX 4090** ($0.44/hr) for good price/perf. An **A100** ($1.64/hr) is overkill but very fast. |
| **Template** | `RunPod Pytorch 2.4.0` (or any PyTorch template) |
| **Container Disk** | 20 GB (minimum) |
| **Volume Disk** | 30 GB (stores model weights across restarts) |
| **Volume Mount** | `/workspace` (default) |
| **Expose HTTP Ports** | `8888` (add this!) |
| **Expose TCP Ports** | `22` (SSH — usually on by default) |

4. Click **Deploy**
5. Wait for the pod to start (status goes from "Creating" to "Running")

### Step 4: Get Your Pod Connection Info

Once the pod is running:

1. Click on the pod name to open its details
2. Note the **Pod ID** — it's in the URL and shown at the top (e.g., `a1b2c3d4e5`)
3. Click the **Connect** button
4. Copy the **SSH command** — it looks like:
   ```
   ssh root@ssh.runpod.io -p 22177 -i ~/.ssh/id_ed25519
   ```
5. Note the **HTTP port 8888 URL** — it looks like:
   ```
   https://a1b2c3d4e5-8888.proxy.runpod.net
   ```

### Step 5: Deploy DiffusionGuard

From your laptop, in this repo directory:

```bash
# Use the SSH args from the Connect page (adjust port number)
./deploy.sh runpod -p 22177 root@ssh.runpod.io
```

Or if the unified deploy script gives you trouble with the SSH port, do it manually:

```bash
# SSH into the pod
ssh root@ssh.runpod.io -p 22177 -i ~/.ssh/id_ed25519

# Now on the pod:
cd /workspace
mkdir -p diffusionguard_project/server

# Clone DiffusionGuard
git clone https://github.com/choi403/DiffusionGuard.git

# Install dependencies (PyTorch is already in the template)
pip install diffusers==0.24.0 transformers datasets huggingface-hub \
  numpy omegaconf opencv-contrib-python scikit-learn tqdm hydra-core flask pillow
```

Then copy the server code. From a **new terminal on your laptop**:

```bash
# Copy server code to the pod
scp -P 22177 server/app.py server/requirements.txt \
  root@ssh.runpod.io:/workspace/diffusionguard_project/server/
```

### Step 6: Start the Server

SSH into the pod and start the server:

```bash
ssh root@ssh.runpod.io -p 22177 -i ~/.ssh/id_ed25519

cd /workspace/diffusionguard_project/server

# Set the DiffusionGuard repo path
export DIFFGUARD_REPO=/workspace/DiffusionGuard

# Start the server (first run downloads the model — ~2-5 min)
python app.py
```

You'll see:
```
Loading runwayml/stable-diffusion-inpainting on cuda (torch.float16)...
Model loaded successfully.
Starting DiffusionGuard + Fawkes API server on :8888
 * Running on http://0.0.0.0:8888
```

### Step 7: Test from Your Laptop

```bash
# Set your pod ID
export RUNPOD_POD_ID=a1b2c3d4e5   # Replace with your actual pod ID

# Health check
curl https://${RUNPOD_POD_ID}-8888.proxy.runpod.net/health

# Protect an image
python client/glaze.py \
  --image test_images/face.png \
  --mask test_images/face_mask.png \
  --backend runpod

# Or use the direct URL
python client/glaze.py \
  --image test_images/face.png \
  --mask test_images/face_mask.png \
  --server https://${RUNPOD_POD_ID}-8888.proxy.runpod.net
```

### Step 8: Update backends.json (Optional)

So you don't have to set `RUNPOD_POD_ID` every time:

Edit `backends.json` and fill in your pod ID:

```json
"runpod": {
    "url": "https://{POD_ID}-8888.proxy.runpod.net",
    "type": "runpod",
    "pod_id": "a1b2c3d4e5"
}
```

Now just `--backend runpod` works with no env vars.

---

## Cost Estimates

| GPU | $/hr | Protect 1 image (200 iters) | Protect 1 image (800 iters) |
|-----|------|----------------------------|----------------------------|
| RTX A4000 | $0.20 | ~30s → $0.002 | ~2min → $0.007 |
| RTX 4090 | $0.44 | ~15s → $0.002 | ~1min → $0.007 |
| A100 80GB | $1.64 | ~8s → $0.004 | ~30s → $0.014 |

The model download only happens once. If you use a **volume**, the weights persist
across pod restarts so you don't re-download.

---

## Keeping the Server Running

If you disconnect from SSH, the server dies. To keep it running in the background:

```bash
# Option A: nohup
cd /workspace/diffusionguard_project/server
export DIFFGUARD_REPO=/workspace/DiffusionGuard
nohup python app.py > /workspace/server.log 2>&1 &

# Check logs later
tail -f /workspace/server.log
```

```bash
# Option B: tmux (if available)
tmux new -s diffguard
cd /workspace/diffusionguard_project/server
export DIFFGUARD_REPO=/workspace/DiffusionGuard
python app.py
# Ctrl+B then D to detach
# tmux attach -t diffguard to reattach
```

---

## Stopping the Pod (Save Money!)

When you're done:

1. Go to [RunPod Pods](https://www.runpod.io/console/pods)
2. Click **Stop** on your pod (keeps the volume, stops billing for GPU)
3. To resume later, click **Start** — your volume with the model weights is still there

To fully delete (removes everything):
- Click **Terminate** — this deletes the pod and volume
