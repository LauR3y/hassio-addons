#!/usr/bin/with-contenv bashio
# ==============================================================================
# Home Assistant Add-on: Buzz Agent
# Validates the options and writes every environment variable to its own file
# under /var/run/buzz-agent/env/, so the service script can load them without
# any secret reaching a command line.
# ==============================================================================
set -e

OPTIONS_FILE=/data/options.json
ENV_DIR=/var/run/buzz-agent/env

install -d -m 0700 /var/run/buzz-agent
install -d -m 0700 "${ENV_DIR}"

# jq's `//` treats false as absent, so it is only safe for strings. Every option
# here is a string or enum; there are no booleans on purpose.
opt() {
    jq -r --arg k "$1" '.[$k] // empty' "${OPTIONS_FILE}"
}

put_env() {
    printf '%s' "$2" > "${ENV_DIR}/$1"
    chmod 600 "${ENV_DIR}/$1"
}

# --- Relay -------------------------------------------------------------------
RELAY_URL="$(opt relay_url)"
if [ -z "${RELAY_URL}" ]; then
    bashio::exit.nok "The 'relay_url' option is required. It must be exactly the same URL the \
Buzz add-on is configured with -- the relay looks a community up by the host you connect to and \
has no fallback."
fi
case "${RELAY_URL}" in
    ws://* | wss://*) ;;
    *) bashio::exit.nok "relay_url must start with ws:// or wss:// (got '${RELAY_URL}')." ;;
esac

OWNER="$(opt owner_pubkey)"
if [ -z "${OWNER}" ]; then
    bashio::exit.nok "The 'owner_pubkey' option is required: it is who the agent takes \
instructions from. Use the same key as the Buzz add-on's owner_pubkey."
fi

# --- Provider ----------------------------------------------------------------
PROVIDER="$(opt provider)"
[ -n "${PROVIDER}" ] || PROVIDER="openrouter"
API_KEY="$(opt api_key)"
MODEL="$(opt model)"
API_BASE_URL="$(opt api_base_url)"

if [ -z "${API_KEY}" ] && [ "${PROVIDER}" != "databricks" ]; then
    bashio::exit.nok "The 'api_key' option is required for provider '${PROVIDER}'."
fi

put_env BUZZ_AGENT_PROVIDER "${PROVIDER}"
case "${PROVIDER}" in
    openrouter)
        put_env OPENROUTER_API_KEY "${API_KEY}"
        [ -n "${MODEL}" ] && put_env OPENROUTER_MODEL "${MODEL}"
        ;;
    anthropic)
        put_env ANTHROPIC_API_KEY "${API_KEY}"
        [ -n "${MODEL}" ] && put_env ANTHROPIC_MODEL "${MODEL}"
        ;;
    openai)
        put_env OPENAI_COMPAT_API_KEY "${API_KEY}"
        [ -n "${MODEL}" ] && put_env OPENAI_COMPAT_MODEL "${MODEL}"
        if [ -z "${API_BASE_URL}" ]; then
            bashio::exit.nok "Provider 'openai' needs 'api_base_url' (for example \
https://api.openai.com/v1, or your own vLLM/llama.cpp/Ollama endpoint)."
        fi
        put_env OPENAI_COMPAT_BASE_URL "${API_BASE_URL}"
        ;;
    databricks)
        if [ -z "${API_BASE_URL}" ]; then
            bashio::exit.nok "Provider 'databricks' needs 'api_base_url' set to your workspace host."
        fi
        put_env DATABRICKS_HOST "${API_BASE_URL}"
        [ -n "${MODEL}" ] && put_env DATABRICKS_MODEL "${MODEL}"
        ;;
esac

# --- Harness -----------------------------------------------------------------
put_env BUZZ_RELAY_URL "${RELAY_URL}"
put_env BUZZ_PRIVATE_KEY "$(cat /data/.secrets/agent_private_key)"
put_env BUZZ_ACP_AGENT_OWNER "${OWNER}"

# The harness defaults to spawning `goose`, which this image does not ship, with
# an `acp` argument that only goose understands. Point it at the bundled agent
# and clear the argument.
put_env BUZZ_ACP_AGENT_COMMAND "buzz-agent"
put_env BUZZ_ACP_AGENT_ARGS ""

RESPOND_TO="$(opt respond_to)"
[ -n "${RESPOND_TO}" ] || RESPOND_TO="owner-only"
put_env BUZZ_ACP_RESPOND_TO "${RESPOND_TO}"

ALLOWLIST="$(opt respond_to_allowlist)"
if [ "${RESPOND_TO}" = "allowlist" ]; then
    if [ -z "${ALLOWLIST}" ]; then
        bashio::exit.nok "respond_to is 'allowlist' but 'respond_to_allowlist' is empty."
    fi
    put_env BUZZ_ACP_RESPOND_TO_ALLOWLIST "${ALLOWLIST}"
fi

SUBSCRIBE="$(opt subscribe)"
[ -n "${SUBSCRIBE}" ] || SUBSCRIBE="mentions"
put_env BUZZ_ACP_SUBSCRIBE "${SUBSCRIBE}"

CHANNELS="$(opt channels)"
[ -n "${CHANNELS}" ] && put_env BUZZ_ACP_CHANNELS "${CHANNELS}"

SYSTEM_PROMPT="$(opt system_prompt)"
[ -n "${SYSTEM_PROMPT}" ] && put_env BUZZ_ACP_SYSTEM_PROMPT "${SYSTEM_PROMPT}"

LOG_LEVEL="$(opt log_level)"
[ -n "${LOG_LEVEL}" ] || LOG_LEVEL="info"
put_env RUST_LOG "buzz_acp=${LOG_LEVEL},buzz_agent=${LOG_LEVEL}"

put_env HOME "/data/agent"

# Profile fields. buzz-acp never publishes a kind:0 profile of its own, so
# without this the agent shows up in Buzz as a bare npub. The service script
# publishes these with `buzz users set-profile` once it can reach the relay.
DISPLAY_NAME="$(opt display_name)"
[ -n "${DISPLAY_NAME}" ] && put_env BUZZ_AGENT_DISPLAY_NAME "${DISPLAY_NAME}"
# Also forwarded to the bundled git tooling, which uses it as the commit author
# name instead of the raw npub.
[ -n "${DISPLAY_NAME}" ] && put_env BUZZ_ACP_DISPLAY_NAME "${DISPLAY_NAME}"
ABOUT="$(opt about)"
[ -n "${ABOUT}" ] && put_env BUZZ_AGENT_ABOUT "${ABOUT}"
AVATAR_URL="$(opt avatar_url)"
[ -n "${AVATAR_URL}" ] && put_env BUZZ_AGENT_AVATAR "${AVATAR_URL}"

bashio::log.info "Agent configured: provider=${PROVIDER} model=${MODEL:-<provider default>} \
respond_to=${RESPOND_TO} subscribe=${SUBSCRIBE}"
bashio::log.info "Relay: ${RELAY_URL}"
bashio::log.info "This must match the Buzz add-on's relay_url exactly, or the relay will answer"
bashio::log.info "'no community is configured for this host'."
