#!/usr/bin/with-contenv bashio
# ==============================================================================
# Home Assistant Add-on: Buzz
# Validates the add-on options, derives every relay environment variable from
# them, and writes each one to its own file under /var/run/buzz/env/ so service
# scripts can load them without interpolating secrets on a command line.
# ==============================================================================
set -e

# shellcheck source=/dev/null
source /usr/lib/buzz/common.sh

put_env() {
    printf '%s' "$2" > "${BUZZ_ENV_DIR}/$1"
    chmod 600 "${BUZZ_ENV_DIR}/$1"
}

# --- relay_url ----------------------------------------------------------------
# This string is the community's primary key. buzz-core's normalize_host()
# lowercases it, strips a trailing dot, and strips ONLY :443 and :80 -- so port
# 3000 stays part of the key, and there is deliberately no fallback community.
RELAY_URL="$(buzz::opt relay_url)"
if [ -z "${RELAY_URL}" ]; then
    bashio::exit.nok "The 'relay_url' option is required."
fi

case "${RELAY_URL}" in
    ws://*)
        HTTP_SCHEME="http"
        AUTHORITY="${RELAY_URL#ws://}"
        ;;
    wss://*)
        HTTP_SCHEME="https"
        AUTHORITY="${RELAY_URL#wss://}"
        ;;
    *)
        bashio::exit.nok "relay_url must start with ws:// or wss:// (got '${RELAY_URL}')."
        ;;
esac

AUTHORITY="${AUTHORITY%/}"
if [[ "${AUTHORITY}" == */* ]]; then
    bashio::exit.nok "relay_url must not contain a path (got '${RELAY_URL}')."
fi
if [ -z "${AUTHORITY}" ]; then
    bashio::exit.nok "relay_url is missing a host (got '${RELAY_URL}')."
fi
AUTHORITY="${AUTHORITY,,}"
AUTHORITY="${AUTHORITY%.}"

# Same default-port collapsing the relay applies when it keys the community.
HOST_AUTHORITY="${AUTHORITY}"
case "${HOST_AUTHORITY}" in
    *:443) HOST_AUTHORITY="${HOST_AUTHORITY%:443}" ;;
    *:80) HOST_AUTHORITY="${HOST_AUTHORITY%:80}" ;;
esac

ORIGIN="${HTTP_SCHEME}://${AUTHORITY}"

# An mDNS name is a trap here. Buzz Desktop resolves it with a Rust HTTP client
# that takes the first address returned and does not fall back, and mDNS
# commonly answers with a link-local IPv6 address first. This add-on publishes
# its port through Docker, which is IPv4-only, so Desktop fails with
# "join policy request failed: error sending request" while a browser still
# works (browsers retry over IPv4).
case "${HOST_AUTHORITY%%:*}" in
    *.local)
        bashio::log.warning "relay_url uses the mDNS name '${HOST_AUTHORITY%%:*}'."
        bashio::log.warning "Buzz Desktop may fail to connect with 'error sending request', because"
        bashio::log.warning ".local often resolves to IPv6 first and this add-on is reachable over"
        bashio::log.warning "IPv4 only. If that happens, set relay_url to the IPv4 address instead"
        bashio::log.warning "(e.g. ws://192.168.1.50:3000) and reserve that address in your router."
        ;;
esac

# Warn loudly when relay_url changes: the relay will create a SECOND community
# for the new host and the existing one becomes unreachable. Warn rather than
# refuse, so a typo can still be corrected before the relay is used for real.
LAST_URL_FILE=/data/relay_url.last
LAST_URL="$(cat "${LAST_URL_FILE}" 2>/dev/null || true)"
if [ -n "${LAST_URL}" ] && [ "${LAST_URL}" != "${RELAY_URL}" ]; then
    bashio::log.warning "=================================================================="
    bashio::log.warning "relay_url changed: '${LAST_URL}' -> '${RELAY_URL}'"
    bashio::log.warning "Buzz keys its community on the exact scheme, host and port."
    bashio::log.warning "The relay will create a SECOND, EMPTY community for the new URL."
    bashio::log.warning "Existing channels, members and repos stay attached to the old URL"
    bashio::log.warning "and will not be visible. Set relay_url back to '${LAST_URL}'"
    bashio::log.warning "to get the original workspace back."
    bashio::log.warning "=================================================================="
fi
printf '%s' "${RELAY_URL}" > "${LAST_URL_FILE}"
chmod 600 "${LAST_URL_FILE}"

# --- owner_pubkey -------------------------------------------------------------
# The relay only warns and ignores a malformed owner pubkey, then refuses to
# start in closed-relay mode, so validate strictly and fail with a clear message.
OWNER="$(buzz::opt owner_pubkey)"
if [ -z "${OWNER}" ]; then
    bashio::exit.nok "The 'owner_pubkey' option is required. In Buzz Desktop: Settings -> Identity -> Public key."
fi
if ! OWNER_HEX="$(buzz::pubkey_to_hex "${OWNER}")"; then
    bashio::exit.nok "owner_pubkey must be a 64-character hex pubkey or an npub1... string (got '${OWNER}')."
fi
bashio::log.info "Relay owner pubkey (hex): ${OWNER_HEX}"
bashio::log.info "Verify that matches Settings -> Identity -> Public key in Buzz Desktop."

# --- Remaining options --------------------------------------------------------
REQUIRE_MEMBERSHIP="$(buzz::opt require_relay_membership)"
[ -n "${REQUIRE_MEMBERSHIP}" ] || REQUIRE_MEMBERSHIP="true"

SERVE_WEB_GUI="$(buzz::opt serve_web_gui)"
[ -n "${SERVE_WEB_GUI}" ] || SERVE_WEB_GUI="true"

LOG_LEVEL="$(buzz::opt log_level)"
[ -n "${LOG_LEVEL}" ] || LOG_LEVEL="info"

# The relay serves its own web bundle, so browser requests to it are same-origin
# and need no CORS entry. This list only matters for a Buzz client served from a
# different origin; extra_cors_origins covers that case.
CORS="${ORIGIN},http://localhost:3000,http://127.0.0.1:3000"
EXTRA_CORS="$(buzz::opt extra_cors_origins)"
if [ -n "${EXTRA_CORS}" ]; then
    CORS="${CORS},${EXTRA_CORS}"
fi

# --- Env files ----------------------------------------------------------------
put_env RELAY_URL "${RELAY_URL}"
put_env RELAY_OWNER_PUBKEY "${OWNER_HEX}"
put_env BUZZ_RELAY_PRIVATE_KEY "$(cat "${BUZZ_SECRETS_DIR}/relay_private_key")"
put_env BUZZ_GIT_HOOK_HMAC_SECRET "$(cat "${BUZZ_SECRETS_DIR}/git_hook_hmac_secret")"

put_env BUZZ_BIND_ADDR "0.0.0.0:3000"
put_env BUZZ_HEALTH_PORT "8080"
put_env BUZZ_METRICS_PORT "9102"
put_env BUZZ_WEB_DIR "/srv/buzz/web"
put_env BUZZ_ADMIN_WEB_DIR "/srv/buzz/admin-web"
put_env BUZZ_SERVE_GIT_WEB_GUI "${SERVE_WEB_GUI}"

put_env DATABASE_URL \
    "postgres://buzz:$(cat "${BUZZ_SECRETS_DIR}/postgres_password")@127.0.0.1:5432/buzz"
put_env REDIS_URL \
    "redis://:$(cat "${BUZZ_SECRETS_DIR}/redis_password")@127.0.0.1:6379"

put_env BUZZ_S3_ENDPOINT "http://127.0.0.1:9000"
put_env BUZZ_S3_ADDRESSING_STYLE "path"
put_env BUZZ_S3_BUCKET "buzz-media"
put_env BUZZ_S3_REGION "us-east-1"
put_env BUZZ_S3_ACCESS_KEY "$(cat "${BUZZ_SECRETS_DIR}/minio_access_key")"
put_env BUZZ_S3_SECRET_KEY "$(cat "${BUZZ_SECRETS_DIR}/minio_secret_key")"

# The relay validates that this ends with /media and does not end with a slash.
put_env BUZZ_MEDIA_BASE_URL "${ORIGIN}/media"
put_env BUZZ_MEDIA_SERVER_DOMAIN "${HOST_AUTHORITY}"
put_env BUZZ_CORS_ORIGINS "${CORS}"

# Upstream default is OFF, which would leave the relay running on an empty schema.
put_env BUZZ_AUTO_MIGRATE "true"
put_env BUZZ_REQUIRE_AUTH_TOKEN "true"
put_env BUZZ_REQUIRE_RELAY_MEMBERSHIP "${REQUIRE_MEMBERSHIP}"
put_env BUZZ_ALLOW_NIP_OA_AUTH "true"

# Upstream default is a relative ./repos, which would land outside /data.
put_env BUZZ_GIT_REPO_PATH "/data/git"
# Keep the pack cache off /data: it is disposable and would otherwise add write
# churn and up to 5 GiB (the upstream default) to the HA data disk.
put_env BUZZ_GIT_PACK_CACHE_PATH "/var/cache/buzz/git-packs"
put_env BUZZ_GIT_PACK_CACHE_MAX_BYTES "268435456"
put_env BUZZ_GIT_MAX_PACK_BYTES "67108864"
put_env BUZZ_GIT_MAX_CONCURRENT_OPS "4"

# Upstream defaults (50 DB / 16 Redis connections) are far too heavy for a Pi.
put_env BUZZ_DB_POOL_SIZE "8"
put_env BUZZ_REDIS_POOL_SIZE "4"

put_env HOME "/data/buzz"
put_env RUST_LOG \
    "buzz_relay=${LOG_LEVEL},buzz_db=${LOG_LEVEL},buzz_auth=${LOG_LEVEL},buzz_pubsub=${LOG_LEVEL},tower_http=${LOG_LEVEL}"

bashio::log.info "Configuration ready (relay_url=${RELAY_URL}, community host=${HOST_AUTHORITY})"
