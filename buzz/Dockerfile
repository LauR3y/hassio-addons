ARG BUILD_FROM

# Upstream Buzz relay image. Pinned by sha tag on purpose:
#   :latest is stale at 0.2.1 (incompatible with current Buzz Desktop)
#   :main moves under us
# sha-6e5c462 == block/buzz relay-v0.2.1 @ 6e5c462ac524de60d7edb46c66130fd779cc9006.
# Bump this together with the add-on version, and re-read migrations/ first.
FROM ghcr.io/block/buzz:sha-6e5c462 AS buzz

# MinIO server + client, same releases upstream's deploy/compose pins. Both are
# static Go binaries, so copying them onto Debian is safe.
# quay.io, not Docker Hub: MinIO withdrew minio/minio and minio/mc from Docker
# Hub (auth.docker.io grants an empty pull scope, so the manifest 401s and the
# build dies with "pull access denied ... insufficient_scope"). quay.io still
# carries these exact release tags for arm64 and amd64.
FROM quay.io/minio/minio:RELEASE.2025-09-07T16-13-09Z AS minio
FROM quay.io/minio/mc:RELEASE.2025-08-13T08-35-41Z AS mc

FROM ${BUILD_FROM}

ARG BUILD_ARCH
ARG BUILD_DATE
ARG BUILD_REF
ARG BUILD_VERSION

# Debian trixie ships postgresql-17 and redis-server in main for both arm64 and
# amd64, so no third-party apt repo is needed. postgresql-common is installed
# first so create_main_cluster can be disabled before postgresql-17's postinst
# builds a cluster we would only have to drop again -- our cluster lives on
# /data and is created at runtime by cont-init.d.
# pgcrypto (needed by buzz migration 0001) ships inside postgresql-17 itself.
# The relay itself needs no libssl (all TLS is rustls); it does shell out to git.
RUN set -eux; \
    printf 'exit 101\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d; \
    apt-get update; \
    apt-get install -y --no-install-recommends postgresql-common; \
    sed -ri 's/#?(create_main_cluster) .*$/\1 = false/' /etc/postgresql-common/createcluster.conf; \
    apt-get install -y --no-install-recommends \
        git \
        postgresql-17 \
        postgresql-client-17 \
        redis-server \
        redis-tools; \
    rm -rf /var/lib/apt/lists/* /usr/sbin/policy-rc.d

COPY --from=minio /usr/bin/minio /usr/local/bin/minio
COPY --from=mc /usr/bin/mc /usr/local/bin/mc

COPY --from=buzz /usr/local/bin/buzz-relay /usr/local/bin/buzz-relay
COPY --from=buzz /usr/local/bin/buzz-admin /usr/local/bin/buzz-admin
# Standalone NIP-AB device-pairing relay. The main relay does not serve /pair,
# so without this, Buzz Desktop's mobile pairing fails with a 404.
COPY --from=buzz /usr/local/bin/buzz-pair-relay /usr/local/bin/buzz-pair-relay
COPY --from=buzz /srv/buzz/web /srv/buzz/web
COPY --from=buzz /srv/buzz/admin-web /srv/buzz/admin-web

# COPY --from inherits no ENV from the source image. BUZZ_WEB_DIR must be set
# and must contain index.html or the relay refuses to start; unset means the
# bundle is silently not served.
ENV BUZZ_WEB_DIR=/srv/buzz/web \
    BUZZ_ADMIN_WEB_DIR=/srv/buzz/admin-web \
    BUZZ_MINIO_RELEASE=RELEASE.2025-09-07T16-13-09Z \
    PATH=/usr/lib/postgresql/17/bin:/command:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# postgres/redis users come from their packages; buzz and minio are ours.
# No uid pinning: /data ownership is fixed at runtime by cont-init.d.
RUN set -eux; \
    useradd --system --home-dir /var/lib/buzz --create-home \
            --shell /usr/sbin/nologin buzz; \
    useradd --system --home-dir /var/lib/minio --create-home \
            --shell /usr/sbin/nologin minio

COPY rootfs /
RUN chmod -R +x /etc/cont-init.d /etc/services.d /usr/lib/buzz

WORKDIR /data

LABEL \
    io.hass.name="Buzz" \
    io.hass.description="Self-hosted Buzz relay with bundled PostgreSQL, Redis and MinIO" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version="${BUILD_VERSION}" \
    maintainer="Laurens Verschuere <hassio@laurensverschuere.be>" \
    org.opencontainers.image.title="Buzz" \
    org.opencontainers.image.description="Self-hosted Buzz relay with bundled PostgreSQL, Redis and MinIO" \
    org.opencontainers.image.source="https://github.com/LauR3y/hassio-addons" \
    org.opencontainers.image.licenses="Apache-2.0" \
    org.opencontainers.image.created="${BUILD_DATE}" \
    org.opencontainers.image.revision="${BUILD_REF}" \
    org.opencontainers.image.version="${BUILD_VERSION}"
