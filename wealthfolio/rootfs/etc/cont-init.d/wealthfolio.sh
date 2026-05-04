#!/usr/bin/with-contenv bashio
# ==============================================================================
# Home Assistant Add-on: Wealthfolio
# Generates WF_SECRET_KEY (auto, persisted) and WF_AUTH_PASSWORD_HASH (argon2id
# of the user's plain password + persisted salt). Written to individual files
# under /var/run/wealthfolio/ so the service script can cat them without any
# shell interpolation of the `$argon2id$...` PHC string.
# ==============================================================================
set -e

OPTIONS_FILE=/data/options.json
DATA_DIR=/data
RUNTIME_DIR=/var/run/wealthfolio
mkdir -p "${DATA_DIR}" "${RUNTIME_DIR}"
chmod 700 "${RUNTIME_DIR}"

# jq -r '...' returns "null" (literal string) for missing keys; map that to empty.
opt() {
    local val
    val="$(jq -r --arg k "$1" '.[$k] // empty' "${OPTIONS_FILE}")"
    printf '%s' "${val}"
}

# --- Secret key ---------------------------------------------------------------
SECRET_FILE="${DATA_DIR}/secret.key"
SECRET_OPT="$(opt secret_key)"
if [ -n "${SECRET_OPT}" ]; then
    SECRET_KEY="${SECRET_OPT}"
elif [ -f "${SECRET_FILE}" ]; then
    SECRET_KEY="$(cat "${SECRET_FILE}")"
else
    SECRET_KEY="$(head -c 32 /dev/urandom | base64)"
    printf '%s' "${SECRET_KEY}" > "${SECRET_FILE}"
    chmod 600 "${SECRET_FILE}"
    bashio::log.info "Generated new WF_SECRET_KEY at ${SECRET_FILE}"
fi
printf '%s' "${SECRET_KEY}" > "${RUNTIME_DIR}/secret_key"
chmod 600 "${RUNTIME_DIR}/secret_key"

# --- Password hash ------------------------------------------------------------
SALT_FILE="${DATA_DIR}/auth.salt"
if [ ! -f "${SALT_FILE}" ]; then
    head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n' > "${SALT_FILE}"
    chmod 600 "${SALT_FILE}"
fi
SALT="$(cat "${SALT_FILE}")"

PASSWORD="$(opt password)"
if [ -z "${PASSWORD}" ]; then
    bashio::exit.nok "The 'password' option is required."
fi

printf '%s' "${PASSWORD}" | argon2 "${SALT}" -id -e > "${RUNTIME_DIR}/password_hash"
chmod 600 "${RUNTIME_DIR}/password_hash"

bashio::log.info "Wealthfolio init complete"
