ARG BUILD_FROM

# Upstream agent runtime image. One statically linked Rust binary that multicalls
# into buzz-acp (the harness), buzz-agent (the LLM agent), buzz-dev-mcp, rg, tree,
# the buzz CLI and the nostr git helpers -- no Node or Python runtime needed.
FROM ghcr.io/block/buzz-sprig:main AS sprig

FROM ${BUILD_FROM}

ARG BUILD_ARCH
ARG BUILD_DATE
ARG BUILD_REF
ARG BUILD_VERSION

# The agent shells out to git for its repository tools; everything else it needs
# (jq, bashio, ca-certificates, curl) is already in the base.
RUN apk add --no-cache git

# sprig is static (musl, no interpreter), so it runs unchanged on this base.
COPY --from=sprig /usr/local/bin/sprig /usr/local/bin/sprig
RUN set -eux; \
    for name in buzz-acp buzz-agent buzz-dev-mcp rg tree buzz \
                git-credential-nostr git-sign-nostr; do \
        ln -s sprig "/usr/local/bin/${name}"; \
    done; \
    adduser -D -h /data/agent agent

# Nostr-signed commits, exactly as the upstream sprig image configures them.
RUN set -eux; \
    git config --system gpg.format x509; \
    git config --system gpg.x509.program /usr/local/bin/git-sign-nostr; \
    git config --system commit.gpgSign true; \
    git config --system tag.gpgSign true

COPY rootfs /
RUN chmod -R +x /etc/cont-init.d /etc/services.d

WORKDIR /data

LABEL \
    io.hass.name="Buzz Agent" \
    io.hass.description="Buzz AI agent connected to your Buzz relay" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version="${BUILD_VERSION}" \
    maintainer="Laurens Verschuere <hassio@laurensverschuere.be>" \
    org.opencontainers.image.title="Buzz Agent" \
    org.opencontainers.image.description="Buzz AI agent connected to your Buzz relay" \
    org.opencontainers.image.source="https://github.com/LauR3y/hassio-addons" \
    org.opencontainers.image.licenses="Apache-2.0" \
    org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.revision="${BUILD_REF}" \
    org.opencontainers.image.version="${BUILD_VERSION}"
