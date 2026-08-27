# Cena — TreeHacks '26
Abhishek Shah, Isaac Chen, Nikhil Vemuri, Ray Zhang (sorted alphabetically)
---

Protect images against malicious AI inpainting using [DiffusionGuard](https://github.com/choi403/DiffusionGuard) (ICLR 2025), running on any GPU backend — ASUS Ascent GX10, RunPod, or any remote GPU.

## Architecture

```
Your Laptop (macOS)                          GPU Backend (GX10 / RunPod / any)
┌──────────────────────┐                     ┌──────────────────────────────┐
│                      │  POST /protect      │                              │
│  client/glaze.py     │ ──────────────────► │  server/app.py (Flask :5000) │
│  --backend gx10      │                     │  ├── DiffusionGuard (PGD)    │
│  --backend runpod    │ ◄────────────────── │  └── SD Inpainting pipeline  │
│  --backend local     │  protected.png      │                              │
└──────────────────────┘                     └──────────────────────────────┘
```

## Project Structure

```
.
├── README.md               # This file
├── SETUP_GX10.md           # Full GX10 hardware + software setup guide
├── backends.json           # Named GPU backends config
├── deploy.sh               # Unified deploy script (gx10 / runpod / ssh)
├── deploy_runpod.sh        # RunPod-specific deploy helper
├── server/
│   ├── app.py              # Flask API server (runs on the GPU box)
│   └── requirements.txt    # Server Python dependencies
├── client/
│   ├── backends.py         # Backend resolver (reads backends.json)
│   ├── glaze.py            # CLI to protect images
│   ├── test_glazing.py     # End-to-end test proving protection works
│   ├── make_test_mask.py   # Generate test masks
│   └── requirements.txt    # Client Python dependencies
└── test_images/            # Put your test images here
```

## Quick Start

### 1. Pick a GPU backend

| Backend | Best for | Deploy command |
|---------|----------|----------------|
| **GX10** | Local network, always-on | `./deploy.sh gx10 nikhil@spark-abcd.local` |
| **RunPod** | On-demand cloud GPU | `./deploy.sh runpod -p 22177 root@ssh.runpod.io` |
| **Any SSH GPU** | Lambda, Vast.ai, etc. | `./deploy.sh ssh ubuntu@my-gpu.com` |
| **Local** | Your own machine with GPU | Run `python server/app.py` directly |

### 2. Deploy the server

#### Option A: ASUS Ascent GX10

Follow [SETUP_GX10.md](SETUP_GX10.md) for initial hardware setup, then:

```bash
./deploy.sh gx10 nikhil@spark-abcd.local
```

Start the server:
```bash
ssh nikhil@spark-abcd.local
docker exec -it diffguard bash -c 'cd /workspace/project/server && python app.py'
```

#### Option B: RunPod

1. Create a GPU pod on [runpod.io](https://runpod.io) (any NVIDIA GPU, expose port 5000)
2. Deploy:
```bash
./deploy.sh runpod -p 22177 root@ssh.runpod.io
```
3. Set your pod ID:
```bash
export RUNPOD_POD_ID=abc123xyz
# Or edit backends.json and set "pod_id": "abc123xyz"
```

#### Option C: Any SSH GPU box

```bash
./deploy.sh ssh ubuntu@my-gpu-server.com
ssh ubuntu@my-gpu-server.com 'cd ~/diffusionguard_project/server && python app.py'
```

#### Option D: Local (your machine has a GPU)

```bash
# Clone DiffusionGuard next to this repo
git clone https://github.com/choi403/DiffusionGuard.git ../DiffusionGuard
pip install -r server/requirements.txt
python server/app.py
```

### 3. Protect an image (from your laptop)

```bash
pip install requests pillow

# Use your configured default backend
python client/glaze.py --image photo.png --mask mask.png

# Or pick a specific backend
python client/glaze.py --image photo.png --mask mask.png --backend gx10
python client/glaze.py --image photo.png --mask mask.png --backend runpod
python client/glaze.py --image photo.png --mask mask.png --backend local

# Or use a direct URL
python client/glaze.py --image photo.png --mask mask.png --server http://192.168.1.42:5000
```

### 4. Test that protection works

```bash
python client/test_glazing.py \
  --image test_images/face.png \
  --mask test_images/face_mask.png \
  --backend gx10 \
  --prompt "a person being arrested"
```

This runs inpainting on both the original and protected images and generates a
side-by-side comparison grid in `test_results/comparison_grid.png`.

## Backend Configuration

Edit `backends.json` to configure your GPU backends:

```json
{
    "backends": {
        "gx10": {
            "url": "http://spark-abcd.local:5000",
            "type": "ssh-docker",
            "ssh": "nikhil@spark-abcd.local"
        },
        "runpod": {
            "url": "https://{POD_ID}-5000.proxy.runpod.net",
            "type": "runpod",
            "pod_id": "your-pod-id-here"
        },
        "lambda": {
            "url": "http://my-lambda-box.com:5000",
            "type": "ssh"
        },
        "local": {
            "url": "http://localhost:5000",
            "type": "local"
        }
    },
    "default": "gx10"
}
```

You can also use environment variables:
```bash
export RUNPOD_POD_ID=abc123       # RunPod pod ID
export DIFFGUARD_BACKEND=runpod   # Default backend name
export DIFFGUARD_SERVER=http://.. # Direct URL override
```

## API Endpoints

| Method | Endpoint        | Description                                     |
|--------|----------------|-------------------------------------------------|
| GET    | `/health`      | Server status + GPU info                        |
| POST   | `/protect`     | Protect an image (multipart: `image` + `mask`)  |
| POST   | `/test-inpaint`| Run inpainting to test protection effectiveness |

### POST /protect

```bash
curl -X POST http://<gpu>:5000/protect \
  -F "image=@photo.png" \
  -F "mask=@mask.png" \
  --output protected.png
```

Query params: `iters` (int, default 200) — PGD optimization iterations.

### POST /test-inpaint

```bash
curl -X POST "http://<gpu>:5000/test-inpaint?prompt=a+person+in+jail" \
  -F "image=@protected.png" \
  -F "mask=@mask.png" \
  --output result.png
```

Query params: `prompt` (str), `steps` (int, default 50), `seed` (int, default 42).

## References

- [DiffusionGuard Paper (ICLR 2025)](https://arxiv.org/abs/2410.05694)
- [DiffusionGuard Code](https://github.com/choi403/DiffusionGuard)
- [ASUS Ascent GX10](https://www.asus.com/us/networking-iot-servers/desktop-ai-supercomputer/ultra-small-ai-supercomputers/asus-ascent-gx10/)
- [RunPod](https://runpod.io)
