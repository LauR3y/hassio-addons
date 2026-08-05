# shellcheck shell=bash
# ==============================================================================
# Home Assistant Add-on: Buzz
# Shared helpers: env loading, bounded readiness waits, bech32 (npub) decoding.
# Sourced by cont-init.d scripts and service run scripts.
# ==============================================================================

BUZZ_RUN_DIR=/var/run/buzz
BUZZ_ENV_DIR="${BUZZ_RUN_DIR}/env"
BUZZ_SECRETS_DIR=/data/.secrets
BUZZ_OPTIONS_FILE=/data/options.json

# Read an add-on option. jq -r prints the literal string "null" for a missing
# key, so `// empty` maps that to an empty string instead.
buzz::opt() {
    jq -r --arg k "$1" '.[$k] // empty' "${BUZZ_OPTIONS_FILE}"
}

# Hex-only secrets: these values get interpolated into DATABASE_URL, REDIS_URL
# and MC_HOST_* URIs, where a base64 '/', '+', ':' or '@' would silently corrupt
# the URI. $1 = number of random bytes (output is 2x that in hex characters).
buzz::rand_hex() {
    head -c "$1" /dev/urandom | od -An -tx1 | tr -d ' \n'
}

# Write a secret file exactly once. Never regenerates while the file is
# non-empty, so restarts, add-on upgrades and HA restores all keep the same
# credentials. $1 = path, $2.. = generator command.
buzz::gen_once() {
    local file="$1"
    shift
    if [ -s "${file}" ]; then
        return 0
    fi
    ( umask 077 && "$@" > "${file}" )
    chmod 600 "${file}"
    bashio::log.info "Generated and persisted $(basename "${file}")"
}

# Export every file in the env dir as a variable named after the file. Values
# are read from disk rather than passed on a command line, so no secret ever
# lands in the process table or a shell history.
buzz::load_env() {
    local file name
    for file in "${BUZZ_ENV_DIR}"/*; do
        [ -f "${file}" ] || continue
        name="$(basename "${file}")"
        export "${name}=$(cat "${file}")"
    done
}

# Decode a bech32 npub into lowercase hex. Deliberately does not verify the
# bech32 checksum -- the caller logs the decoded hex so it can be eyeballed
# against Buzz Desktop. Returns 1 on anything malformed.
buzz::npub_to_hex() {
    local npub="${1,,}"
    local charset="qpzry9x8gf2tvdw0s3jn54khce6mua7l"
    local data bits hex char prefix value i bit

    data="${npub#npub1}"
    [ "${data}" = "${npub}" ] && return 1
    # 52 data characters + 6 checksum characters for a 32-byte payload.
    [ "${#data}" -eq 58 ] || return 1
    data="${data:0:52}"

    bits=""
    for ((i = 0; i < ${#data}; i++)); do
        char="${data:i:1}"
        prefix="${charset%%"${char}"*}"
        # An unchanged prefix means the character is not in the bech32 charset.
        [ "${prefix}" = "${charset}" ] && return 1
        value=${#prefix}
        for ((bit = 4; bit >= 0; bit--)); do
            bits+="$(((value >> bit) & 1))"
        done
    done

    # 52 * 5 = 260 bits; the payload is the first 256, the rest is padding.
    hex=""
    for ((i = 0; i + 8 <= 256; i += 8)); do
        hex+="$(printf '%02x' "$((2#${bits:i:8}))")"
    done
    printf '%s' "${hex}"
}

# Normalise a pubkey option (64-char hex or npub1...) to lowercase hex.
buzz::pubkey_to_hex() {
    local input="$1" hex
    if [[ "${input}" =~ ^[0-9a-fA-F]{64}$ ]]; then
        printf '%s' "${input,,}"
        return 0
    fi
    if [[ "${input}" == npub1* ]]; then
        hex="$(buzz::npub_to_hex "${input}")" || return 1
        printf '%s' "${hex}"
        return 0
    fi
    return 1
}

buzz::wait_postgres() {
    local deadline=$((SECONDS + 120))
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        if pg_isready -h 127.0.0.1 -p 5432 -U buzz -d buzz -q; then
            return 0
        fi
        sleep 2
    done
    bashio::exit.nok "PostgreSQL did not accept connections on 127.0.0.1:5432 within 120s. \
Check the 'postgres' lines in the log above. If /data/postgres is corrupt, restore a backup; \
deleting it re-initialises the cluster and destroys all Buzz data."
}

buzz::wait_redis() {
    local deadline=$((SECONDS + 60))
    # REDISCLI_AUTH keeps the password out of argv (redis-cli -a warns about it).
    export REDISCLI_AUTH="$(cat "${BUZZ_SECRETS_DIR}/redis_password")"
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        if [ "$(redis-cli -h 127.0.0.1 -p 6379 ping 2>/dev/null)" = "PONG" ]; then
            unset REDISCLI_AUTH
            return 0
        fi
        sleep 1
    done
    unset REDISCLI_AUTH
    bashio::exit.nok "Redis did not answer PING on 127.0.0.1:6379 within 60s. \
Check the 'redis' lines in the log above."
}

buzz::wait_minio() {
    local deadline=$((SECONDS + 180))
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        if curl -fsS -m 3 http://127.0.0.1:9000/minio/health/live > /dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    bashio::exit.nok "MinIO did not report /minio/health/live within 180s. Check the 'minio' \
lines in the log above; first-time formatting of /data/minio is slow on an SD card."
}

# Used by the bootstrap service only. $1 = timeout in seconds. Returns 1 rather
# than exiting, because that service must never take the supervision tree down.
buzz::wait_relay_ready() {
    local deadline=$((SECONDS + ${1:-600}))
    while [ "${SECONDS}" -lt "${deadline}" ]; do
        if curl -fsS -m 3 http://127.0.0.1:8080/_readiness > /dev/null 2>&1; then
            return 0
        fi
        sleep 3
    done
    return 1
}
