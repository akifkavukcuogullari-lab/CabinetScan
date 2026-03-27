FROM nvidia/cuda:12.6.3-runtime-ubuntu24.04

# System deps (libgl1 replaces libgl1-mesa-glx on Ubuntu 24.04)
RUN apt-get update && apt-get install -y \
    python3.12 python3-pip python3.12-venv git curl \
    ffmpeg libgl1 libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python deps
COPY requirements.txt .
RUN pip3 install --no-cache-dir --break-system-packages -r requirements.txt

# SAM 3 BPE tokenizer vocab — ensure it's in the installed package AND /app/assets.
# The file lives at sam3/assets/ in the repo (not top-level assets/).
# Also place it in the pip site-packages in case pip didn't include it.
RUN mkdir -p /app/assets && \
    curl -fSL -o /app/assets/bpe_simple_vocab_16e6.txt.gz \
      "https://github.com/facebookresearch/sam3/raw/refs/heads/main/sam3/assets/bpe_simple_vocab_16e6.txt.gz" && \
    SITE_PKG=$(python3 -c "import site; print(site.getsitepackages()[0])") && \
    mkdir -p "$SITE_PKG/sam3/assets" && \
    cp /app/assets/bpe_simple_vocab_16e6.txt.gz "$SITE_PKG/sam3/assets/" && \
    echo "BPE vocab file:" && ls -la /app/assets/bpe_simple_vocab_16e6.txt.gz

# Copy pipeline code
COPY . .

# Models (SAM 3, Depth Anything) are downloaded at first startup via HF_TOKEN
# Set HF_TOKEN in RunPod environment variables for gated model access

# RunPod entry point
CMD ["python3", "-u", "runpod_handler.py"]
