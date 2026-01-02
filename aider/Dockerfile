ARG BUILD_FROM=ghcr.io/hassio-addons/base:17.0.0
FROM ${BUILD_FROM}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install Python, git, ttyd and build dependencies
RUN apk add --no-cache \
    python3 \
    py3-pip \
    py3-virtualenv \
    git \
    git-lfs \
    openssh-client \
    bash \
    ttyd \
    # Build dependencies for pip packages
    && apk add --no-cache --virtual .build-deps \
        python3-dev \
        gcc \
        musl-dev \
        libffi-dev \
    # Create venv and install aider
    && python3 -m venv /opt/aider-venv \
    && . /opt/aider-venv/bin/activate \
    && pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir aider-chat \
    && deactivate \
    # Cleanup
    && apk del .build-deps \
    && rm -rf /root/.cache /tmp/*

# Add aider to PATH
ENV PATH="/opt/aider-venv/bin:${PATH}"

# Copy root filesystem
COPY rootfs /
