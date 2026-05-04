ARG BUILD_FROM
FROM ghcr.io/afadil/wealthfolio:latest AS upstream

FROM ${BUILD_FROM}

RUN apk add --no-cache argon2

COPY --from=upstream /usr/local/bin/wealthfolio-server /usr/local/bin/wealthfolio-server
COPY --from=upstream /app/dist /app/dist

COPY rootfs /

WORKDIR /app
