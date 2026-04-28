# ============================================================
# AI Engineering from Scratch
# https://github.com/rohitg00/ai-engineering-from-scratch
# ============================================================
# Multi-stage build: supports Python, Node/TypeScript, Rust, Julia
# Usage: see docker-compose.yml or build instructions below
# ============================================================

# ------------------------------------------------------------
# Stage 1: Base Python + system tools
# ------------------------------------------------------------
FROM python:3.11-slim AS base

LABEL maintainer="ai-engineering-from-scratch"
LABEL description="Full environment for AI Engineering from Scratch course"

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# System dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    wget \
    git \
    ca-certificates \
    libssl-dev \
    libffi-dev \
    libgomp1 \
    libsndfile1 \
    ffmpeg \
    pkg-config \
    cmake \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# Stage 2: Rust toolchain
# ------------------------------------------------------------
FROM base AS rust-builder

RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --default-toolchain stable
ENV PATH="/root/.cargo/bin:${PATH}"
RUN rustup component add rustfmt clippy

# ------------------------------------------------------------
# Stage 3: Node.js + TypeScript
# ------------------------------------------------------------
FROM base AS node-builder

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g typescript ts-node @anthropic-ai/sdk \
    && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# Stage 4: Final image (all runtimes combined)
# ------------------------------------------------------------
FROM base AS final

WORKDIR /workspace

# ── Python packages ──────────────────────────────────────────
# Math & ML fundamentals
RUN pip install --upgrade pip && pip install \
    numpy \
    scipy \
    sympy \
    matplotlib \
    seaborn \
    plotly \
    pandas \
    scikit-learn \
    statsmodels \
    # Deep learning
    torch \
    torchvision \
    torchaudio \
    --index-url https://download.pytorch.org/whl/cpu \
    && pip install \
    jax \
    jaxlib \
    flax \
    optax \
    # NLP & LLM
    transformers \
    tokenizers \
    datasets \
    accelerate \
    peft \
    trl \
    sentence-transformers \
    tiktoken \
    openai \
    anthropic \
    # Vision
    opencv-python-headless \
    Pillow \
    timm \
    # Audio / speech
    librosa \
    soundfile \
    speechbrain \
    openai-whisper \
    # Vector DB & RAG
    chromadb \
    faiss-cpu \
    langchain \
    langchain-community \
    # Experiment tracking & infra
    mlflow \
    wandb \
    tensorboard \
    # Notebooks & utilities
    jupyter \
    jupyterlab \
    ipywidgets \
    ipykernel \
    tqdm \
    python-dotenv \
    requests \
    httpx \
    pydantic \
    fastapi \
    uvicorn \
    # Evaluation
    evaluate \
    rouge-score \
    nltk \
    sacrebleu

# ── Node.js + TypeScript ─────────────────────────────────────
COPY --from=node-builder /usr/bin/node /usr/bin/node
COPY --from=node-builder /usr/lib/node_modules /usr/lib/node_modules
COPY --from=node-builder /usr/bin/npm /usr/bin/npm
COPY --from=node-builder /usr/bin/npx /usr/bin/npx
RUN ln -sf /usr/lib/node_modules/.bin/tsc /usr/local/bin/tsc \
    && ln -sf /usr/lib/node_modules/.bin/ts-node /usr/local/bin/ts-node 2>/dev/null || true

# ── Rust ─────────────────────────────────────────────────────
COPY --from=rust-builder /root/.cargo /root/.cargo
COPY --from=rust-builder /root/.rustup /root/.rustup
ENV PATH="/root/.cargo/bin:${PATH}"

# ── Julia (lightweight install) ──────────────────────────────
ARG JULIA_VERSION=1.10.2
RUN wget -q https://julialang-s3.julialang.org/bin/linux/x64/1.10/julia-${JULIA_VERSION}-linux-x86_64.tar.gz \
    && tar -xzf julia-${JULIA_VERSION}-linux-x86_64.tar.gz \
    && mv julia-${JULIA_VERSION} /opt/julia \
    && ln -s /opt/julia/bin/julia /usr/local/bin/julia \
    && rm julia-${JULIA_VERSION}-linux-x86_64.tar.gz

# Install core Julia packages
RUN julia -e 'using Pkg; Pkg.add(["LinearAlgebra", "Statistics", "Plots", "Flux", "DataFrames"])'

# ── Project files ─────────────────────────────────────────────
COPY . /workspace/

# Install project-level requirements if present
RUN if [ -f requirements.txt ]; then pip install -r requirements.txt; fi

# Install Node dependencies if package.json exists
RUN if [ -f package.json ]; then npm install; fi

# ── Jupyter config ────────────────────────────────────────────
RUN jupyter notebook --generate-config && \
    echo "c.NotebookApp.ip = '0.0.0.0'" >> /root/.jupyter/jupyter_notebook_config.py && \
    echo "c.NotebookApp.open_browser = False" >> /root/.jupyter/jupyter_notebook_config.py && \
    echo "c.NotebookApp.allow_root = True" >> /root/.jupyter/jupyter_notebook_config.py && \
    echo "c.NotebookApp.token = ''" >> /root/.jupyter/jupyter_notebook_config.py && \
    echo "c.NotebookApp.password = ''" >> /root/.jupyter/jupyter_notebook_config.py

# ── Ports ────────────────────────────────────────────────────
# 8888 - JupyterLab
# 8000 - FastAPI / uvicorn dev server
EXPOSE 8888 8000

# ── Entrypoint ────────────────────────────────────────────────
CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser", \
     "--allow-root", "--NotebookApp.token=''", "--NotebookApp.password=''"]
