#!/usr/bin/with-contenv bashio
# ==============================================================================
# Home Assistant Add-on: Buzz
# Creates the /data layout and generates every secret exactly once. Nothing here
# is ever regenerated while its file is non-empty, so restarts, add-on upgrades
# and HA restores all keep the same relay identity and credentials.
# ==============================================================================
set -e

# shellcheck source=/dev/null
source /usr/lib/buzz/common.sh

# Every service user (postgres, redis, minio, buzz) needs to traverse /data to
# reach its own subdirectory. Each subdirectory below sets its own restrictive
# mode and .secrets stays root-only, so this grants traversal and nothing more.
chmod 0755 /data

install -d -m 0700 "${BUZZ_SECRETS_DIR}"
# The runtime directory must be traversable by the service users (redis reads
# its config from here); the secrets it holds are protected per file, and the
# env directory below stays root-only.
install -d -m 0755 "${BUZZ_RUN_DIR}"
install -d -m 0700 "${BUZZ_ENV_DIR}"
install -d -o buzz -g buzz -m 0750 /data/git /data/buzz
install -d -o buzz -g buzz -m 0750 /var/cache/buzz/git-packs
install -d -o redis -g redis -m 0750 /data/redis

buzz::gen_once "${BUZZ_SECRETS_DIR}/postgres_password" buzz::rand_hex 24
buzz::gen_once "${BUZZ_SECRETS_DIR}/redis_password" buzz::rand_hex 24
buzz::gen_once "${BUZZ_SECRETS_DIR}/minio_access_key" buzz::rand_hex 10
buzz::gen_once "${BUZZ_SECRETS_DIR}/minio_secret_key" buzz::rand_hex 24
# The relay rejects a git hook HMAC secret shorter than 32 characters.
buzz::gen_once "${BUZZ_SECRETS_DIR}/git_hook_hmac_secret" buzz::rand_hex 32

# --- Relay identity -----------------------------------------------------------
# This key IS the relay's Nostr identity: it is published in the NIP-11 document
# and signs the kind:13534 membership roster. Regenerating it permanently changes
# who this relay is, so it is generated once and read from disk forever after.
RELAY_KEY_FILE="${BUZZ_SECRETS_DIR}/relay_private_key"
if [ ! -s "${RELAY_KEY_FILE}" ]; then
    # `buzz-admin generate-key` prints "Public key:  <hex>" / "Secret key:  <hex>".
    KEY="$(/usr/local/bin/buzz-admin generate-key 2>/dev/null | awk '/^Secret key:/ {print $3; exit}' || true)"
    if [[ ! "${KEY}" =~ ^[0-9a-fA-F]{64}$ ]]; then
        bashio::log.warning "Could not parse 'buzz-admin generate-key' output; falling back to /dev/urandom."
        KEY="$(buzz::rand_hex 32)"
    fi
    ( umask 077 && printf '%s' "${KEY,,}" > "${RELAY_KEY_FILE}" )
    chmod 600 "${RELAY_KEY_FILE}"
    unset KEY
    bashio::log.info "Generated this relay's identity key."
    bashio::log.notice "BACK UP ${RELAY_KEY_FILE} -- losing or replacing it permanently changes this relay's identity."
fi

# A recursive chown over many git repositories is slow on an SD card, so only
# fix the tree when the top directory owner is actually wrong.
if [ "$(stat -c %U /data/git)" != "buzz" ]; then
    chown -R buzz:buzz /data/git
fi

bashio::log.info "Secrets and /data layout ready"
