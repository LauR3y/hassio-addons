#!/usr/bin/with-contenv bashio
# ==============================================================================
# Home Assistant Add-on: Buzz Agent
# Generates the agent's own Nostr identity once, then prints its public key so
# it can be added to the relay's member list. Standalone bot identity: the agent
# authenticates with its own key rather than reusing the owner's, so it can be
# revoked on its own (see examples/countdown-bot in block/buzz).
# ==============================================================================
set -e

SECRETS_DIR=/data/.secrets
KEY_FILE="${SECRETS_DIR}/agent_private_key"
PUBKEY_FILE=/data/agent_pubkey

install -d -m 0700 "${SECRETS_DIR}"
install -d -o agent -g agent -m 0750 /data/agent /data/workspace

if [ ! -s "${KEY_FILE}" ]; then
    # Hex only: this value is passed as BUZZ_PRIVATE_KEY, and the harness also
    # accepts nsec, but hex avoids any encoding ambiguity.
    ( umask 077 && head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "${KEY_FILE}" )
    chmod 600 "${KEY_FILE}"
    bashio::log.info "Generated this agent's identity key."
    bashio::log.notice "Back up ${KEY_FILE} -- replacing it gives the agent a new identity,"
    bashio::log.notice "which you would then have to re-add to the relay."
fi

# Derive the public key by asking the harness itself: it logs
# "buzz-acp starting: relay=... pubkey=<hex> ..." before touching the network.
# The relay URL points at a closed port and the agent command is /bin/true, so
# nothing real is started -- this only reads back the identity.
if [ ! -s "${PUBKEY_FILE}" ]; then
    PUBKEY="$(
        BUZZ_PRIVATE_KEY="$(cat "${KEY_FILE}")" \
        BUZZ_RELAY_URL="ws://127.0.0.1:9/" \
        BUZZ_ACP_AGENT_COMMAND=/bin/true \
        BUZZ_ACP_AGENT_ARGS= \
        timeout 10 /usr/local/bin/buzz-acp 2>&1 \
            | grep -oE 'pubkey=[0-9a-f]{64}' | head -1 | cut -d= -f2 || true
    )"
    if [ -n "${PUBKEY}" ]; then
        printf '%s' "${PUBKEY}" > "${PUBKEY_FILE}"
        chmod 644 "${PUBKEY_FILE}"
    fi
fi

if [ -s "${PUBKEY_FILE}" ]; then
    bashio::log.info "================================================================"
    bashio::log.info "This agent's public key:"
    bashio::log.info "  $(cat "${PUBKEY_FILE}")"
    bashio::log.info ""
    bashio::log.info "Add it to the Buzz add-on's 'members' option and restart that"
    bashio::log.info "add-on, or the relay will reject this agent as 'not a relay member'."
    bashio::log.info "================================================================"
else
    bashio::log.warning "Could not determine the agent's public key; it is logged by the"
    bashio::log.warning "agent service itself at startup as 'pubkey=<hex>'."
fi
