#!/usr/bin/with-contenv bashio
# ==============================================================================
# Home Assistant Add-on: Buzz Agent
# Generates the agent's own Nostr identity key(s) on first start, then prints
# the public key(s) so they can be added to the relay's member list.
#
# Single-agent mode (agents option is empty): one key at the legacy path,
# identical to 0.1.x.
#
# Multi-agent mode (agents option is a JSON array): one key per agent at
# /data/.secrets/agent_<index>_private_key, with the legacy key auto-migrated
# to agent_0 on upgrade.
# ==============================================================================
set -e

OPTIONS_FILE=/data/options.json
SECRETS_DIR=/data/.secrets
KEY_FILE_LEGACY="${SECRETS_DIR}/agent_private_key"

install -d -m 0700 "${SECRETS_DIR}"
install -d -o agent -g agent -m 0750 /data/agent /data/workspace

# Derive a public key from a hex private key by asking buzz-acp. It logs
# "pubkey=<hex>" before touching the network. The dummy relay URL and /bin/true
# agent command ensure nothing real starts.
derive_pubkey() {
    local key_file="$1"
    BUZZ_PRIVATE_KEY="$(cat "${key_file}")" \
    BUZZ_RELAY_URL="ws://127.0.0.1:9/" \
    BUZZ_ACP_AGENT_COMMAND=/bin/true \
    BUZZ_ACP_AGENT_ARGS= \
    timeout 10 /usr/local/bin/buzz-acp 2>&1 \
        | grep -oE 'pubkey=[0-9a-f]{64}' | head -1 | cut -d= -f2 || true
}

# Read the agents option (str? — a JSON array string, possibly empty)
AGENTS_JSON="$(jq -r '.agents // empty' "${OPTIONS_FILE}")"
AGENT_COUNT=0
if [ -n "${AGENTS_JSON}" ] && [ "${AGENTS_JSON}" != "[]" ]; then
    AGENT_COUNT="$(printf '%s' "${AGENTS_JSON}" | jq 'length')"
fi

if [ "${AGENT_COUNT}" -eq 0 ]; then
    # ----------------------------------------------------------------------
    # Single-agent mode (backward compatible with 0.1.x)
    # ----------------------------------------------------------------------
    KEY_FILE="${KEY_FILE_LEGACY}"
    PUBKEY_FILE=/data/agent_pubkey

    if [ ! -s "${KEY_FILE}" ]; then
        ( umask 077 && head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "${KEY_FILE}" )
        chmod 600 "${KEY_FILE}"
        bashio::log.info "Generated this agent's identity key."
        bashio::log.notice "Back up ${KEY_FILE} -- replacing it gives the agent a new identity,"
        bashio::log.notice "which you would then have to re-add to the relay."
    fi

    if [ ! -s "${PUBKEY_FILE}" ]; then
        PUBKEY="$(derive_pubkey "${KEY_FILE}")"
        if [ -n "${PUBKEY}" ]; then
            printf '%s' "${PUBKEY}" > "${PUBKEY_FILE}"
            chmod 644 "${PUBKEY_FILE}"
        fi
    fi

    if [ -s "${PUBKEY_FILE}" ]; then
        bashio::log.info "================================================================================"
        bashio::log.info "This agent's public key:"
        bashio::log.info "  $(cat "${PUBKEY_FILE}")"
        bashio::log.info ""
        bashio::log.info "Add it to the Buzz add-on's 'members' option and restart that"
        bashio::log.info "add-on, or the relay will reject this agent as 'not a relay member'."
        bashio::log.info "================================================================================"
    else
        bashio::log.warning "Could not determine the agent's public key; it is logged by the"
        bashio::log.warning "agent service itself at startup as 'pubkey=<hex>'."
    fi
else
    # ----------------------------------------------------------------------
    # Multi-agent mode
    # ----------------------------------------------------------------------
    install -d -o agent -g agent -m 0750 /data/agents

    # Auto-migrate the legacy single-agent key to agent_0 on first upgrade.
    if [ -s "${KEY_FILE_LEGACY}" ] && [ ! -s "${SECRETS_DIR}/agent_0_private_key" ]; then
        cp "${KEY_FILE_LEGACY}" "${SECRETS_DIR}/agent_0_private_key"
        chmod 600 "${SECRETS_DIR}/agent_0_private_key"
        bashio::log.info "Migrated legacy identity key to agent_0_private_key."
    fi

    for i in $(seq 0 $((AGENT_COUNT - 1))); do
        KEY_FILE="${SECRETS_DIR}/agent_${i}_private_key"
        PUBKEY_FILE="/data/agents/${i}_pubkey"

        install -d -o agent -g agent -m 0750 "/data/agents/${i}" "/data/agents/${i}/workspace"

        if [ ! -s "${KEY_FILE}" ]; then
            ( umask 077 && head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "${KEY_FILE}" )
            chmod 600 "${KEY_FILE}"
            bashio::log.info "Generated identity key for agent ${i}."
        fi

        if [ ! -s "${PUBKEY_FILE}" ]; then
            PUBKEY="$(derive_pubkey "${KEY_FILE}")"
            if [ -n "${PUBKEY}" ]; then
                printf '%s' "${PUBKEY}" > "${PUBKEY_FILE}"
                chmod 644 "${PUBKEY_FILE}"
            fi
        fi
    done

    bashio::log.info "================================================================================"
    bashio::log.info "Agent public keys:"
    for i in $(seq 0 $((AGENT_COUNT - 1))); do
        PUBKEY_FILE="/data/agents/${i}_pubkey"
        if [ -s "${PUBKEY_FILE}" ]; then
            bashio::log.info "  Agent ${i}: $(cat "${PUBKEY_FILE}")"
        fi
    done
    bashio::log.info ""
    bashio::log.info "Add each key to the Buzz add-on's 'members' option and restart that"
    bashio::log.info "add-on, or the relay will reject the agents as 'not relay members'."
    bashio::log.info "================================================================================"
fi
