ARG BUILD_FROM
# Use official aider image as base (it has everything pre-built)
FROM paulgauthier/aider-full:latest

USER root

# Install dependencies and ttyd
RUN apt-get update && apt-get install -y --no-install-recommends \
    jq \
    wget \
    tmux \
    && ARCH=$(dpkg --print-architecture) \
    && if [ "$ARCH" = "arm64" ]; then TTYD_ARCH="aarch64"; else TTYD_ARCH="x86_64"; fi \
    && wget -qO /usr/local/bin/ttyd "https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.${TTYD_ARCH}" \
    && chmod +x /usr/local/bin/ttyd \
    && apt-get remove -y wget \
    && apt-get autoremove -y \
    && rm -rf /var/lib/apt/lists/*

# Copy startup scripts
COPY rootfs /

# Make scripts executable
RUN chmod +x /init.sh

WORKDIR /config

# Use custom entrypoint for HA integration
ENTRYPOINT ["/init.sh"]
