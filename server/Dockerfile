FROM nvidia/cuda:12.1.0-runtime-ubuntu22.04

# System deps
RUN apt-get update && apt-get install -y \
    python3.11 python3-pip python3.11-venv \
    ffmpeg libgl1-mesa-glx libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python deps
COPY requirements.txt .
RUN pip3 install --no-cache-dir -r requirements.txt

# Copy pipeline code
COPY . .

# Download models at build time (cached in Docker layer)
# RUN python3 -c "from pipeline.stages.depth_estimation import DepthEstimator; DepthEstimator.download_model()"

# RunPod entry point
CMD ["python3", "-u", "runpod_handler.py"]
