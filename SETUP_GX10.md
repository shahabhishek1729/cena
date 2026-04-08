# ASUS Ascent GX10 — Full Setup Guide (Out of the Box)

## Hardware: What's in the Box

- ASUS Ascent GX10 unit (150x150x51mm, 1.48kg)
- 240W power adapter + cable
- Quick Start Guide (has your mDNS hostname printed on it, e.g. `spark-abcd`)
- HDMI 2.1 cable (or bring your own)

## Phase 1: First Boot (Needs Monitor + Keyboard)

You need a monitor and keyboard plugged directly into the GX10 for initial setup.

### 1.1 Connect peripherals

1. Plug the **240W power adapter** into the GX10 and wall power.
2. Connect a **monitor** via the HDMI 2.1 port.
3. Connect a **USB keyboard** (and optionally a mouse) via the USB-C ports.
4. Press the **power button**. The GX10 boots into NVIDIA DGX OS (Ubuntu 24.04).

### 1.2 Create your local user account

On first boot, the OS setup wizard appears:

1. Select your **language** and **timezone**.
2. Create a **username** and **password** — remember these, you'll SSH with them.
3. Configure **Wi-Fi** or plug in an **Ethernet cable** (the GX10 has 10G Ethernet).
4. Let the system finish setup and reach the Ubuntu desktop.

### 1.3 Note your hostname and IP

Open a terminal on the GX10 desktop (Ctrl+Alt+T) and run:

```bash
hostname          # e.g. "spark-abcd"
hostname -I       # e.g. "192.168.1.42"
```

Write these down. Your mDNS hostname is also printed on the Quick Start Guide card.

### 1.4 Verify the GPU is detected

```bash
nvidia-smi
```

You should see the NVIDIA Blackwell GPU with 128GB memory. If this fails, the system
needs a firmware update (see Phase 4).

## Phase 2: Enable SSH (So You Can Unplug the Monitor)

### 2.1 Ensure SSH server is running

```bash
sudo systemctl status ssh
# If not active:
sudo systemctl enable --now ssh
```

### 2.2 Test SSH from your laptop

From your **laptop** (on the same network), open a terminal:

```bash
# Using mDNS hostname (preferred)
ssh <username>@spark-abcd.local

# Or using IP address
ssh <username>@192.168.1.42
```

Type `yes` for the fingerprint prompt, enter your password. You're in.

**From this point on, you can unplug the monitor and keyboard.** Everything is done over SSH.

## Phase 3: Docker + NGC Container Setup

The GX10 comes with Docker pre-installed. We need the NVIDIA PyTorch NGC container
for Blackwell (sm_121) GPU support.

### 3.1 Add yourself to the docker group (if needed)

```bash
# Test if docker works without sudo
docker ps

# If permission denied:
sudo usermod -aG docker $USER
newgrp docker
```

### 3.2 Pull the NGC PyTorch container

**Critical:** You must use version `26.01` or later for Blackwell architecture support.

```bash
docker pull nvcr.io/nvidia/pytorch:26.01-py3
```

This is a large download (~15-20GB). Wait for it to finish.

### 3.3 Create a persistent project directory

```bash
mkdir -p ~/diffusionguard_project
```

### 3.4 Launch the container

```bash
docker run -dt \
  --name diffguard \
  --gpus all \
  --ipc=host \
  --ulimit memlock=-1 \
  --ulimit stack=67108864 \
  -p 8888:8888 \
  -v ~/diffusionguard_project:/workspace/project \
  nvcr.io/nvidia/pytorch:26.01-py3
```

### 3.5 Enter the container and verify GPU

```bash
docker exec -it diffguard bash

# Inside the container:
python -c "import torch; print(f'CUDA available: {torch.cuda.is_available()}'); print(f'Arch list: {torch.cuda.get_arch_list()}'); print(f'GPU: {torch.cuda.get_device_name(0)}')"
```

You should see `sm_120` or `sm_121` in the arch list. If you only see up to `sm_90`,
your container image is too old.

### 3.6 Install DiffusionGuard + dependencies

Still inside the container:

```bash
cd /workspace/project

# Clone DiffusionGuard
git clone https://github.com/choi403/DiffusionGuard.git

# Install Python dependencies (skip torch — already in NGC container)
pip install diffusers==0.24.0 transformers datasets huggingface-hub \
  numpy omegaconf opencv-contrib-python scikit-learn tqdm hydra-core flask pillow

# Copy our server code into the project
# (you'll scp this from your laptop — see below)
```

### 3.7 Copy our server code to the GX10

From your **laptop**, in this repo directory:

```bash
scp -r server/ <username>@spark-abcd.local:~/diffusionguard_project/
```

### 3.8 Start the DiffusionGuard API server

```bash
docker exec -it diffguard bash
cd /workspace/project/server
python app.py
```

The first run will download the Stable Diffusion Inpainting model (~4GB) from HuggingFace.
After that, you'll see: `* Running on http://0.0.0.0:8888`

## Phase 4: Firmware Updates (If Needed)

If `nvidia-smi` fails or you have issues, update firmware via the DGX Dashboard:

```bash
# Open the DGX Dashboard (accessible on the GX10 itself at port 11000)
# Or from your laptop via SSH tunnel:
ssh -L 11000:localhost:11000 <username>@spark-abcd.local
# Then open http://localhost:11000 in your browser
```

For offline firmware updates, download packages from the ASUS support page:
https://www.asus.com/support/faq/1056213/

## Phase 5: Daily Usage

After the one-time setup, your daily workflow is:

```bash
# 1. SSH into the GX10
ssh <username>@spark-abcd.local

# 2. Start the container (if stopped)
docker start diffguard

# 3. Start the API server
docker exec -it diffguard bash -c "cd /workspace/project/server && python app.py"

# 4. From your laptop, use the client to protect images
python client/glaze.py --image photo.png --mask mask.png --server http://spark-abcd.local:8888
```

## Network Diagram

```
┌──────────────┐                              ┌─────────────────────────┐
│  Your Laptop │   POST /protect              │   ASUS Ascent GX10      │
│  (macOS)     │   (image + mask)             │   (DGX OS / Docker)     │
│              │ ────────────────────────────► │                         │
│  client/     │                              │   server/app.py         │
│  glaze.py    │ ◄──────────────────────────  │   (Flask + DiffGuard)   │
│              │   200 OK (protected.png)     │   GPU: Blackwell 128GB  │
└──────────────┘                              └─────────────────────────┘
```
