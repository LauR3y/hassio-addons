ARG BUILD_FROM=ghcr.io/hassio-addons/base:17.0.0
# Use official aider image to get pre-built aider
FROM paulgauthier/aider-full:latest AS aider-source

# Build the add-on from Home Assistant base
FROM ${BUILD_FROM}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Install Python, git, and ttyd
RUN apk add --no-cache \
    python3 \
    py3-pip \
    git \
    git-lfs \
    openssh-client \
    bash \
    ttyd

# Copy the entire aider virtual environment from the official image
COPY --from=aider-source /venv /opt/aider-venv

# Add aider to PATH
ENV PATH="/opt/aider-venv/bin:${PATH}"

# Copy root filesystem - v0.1.3
COPY rootfs /
