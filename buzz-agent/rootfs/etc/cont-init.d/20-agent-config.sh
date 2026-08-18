#!/usr/bin/with-contenv bashio
# ==============================================================================
# Home Assistant Add-on: Buzz Agent
# Validates the options and writes every environment variable to its own file
# under /var/run/buzz-agent/env/ (single-agent) or /var/run/buzz-agent/agents/<i>/env/
# (multi-agent), so the service script can load them without any secret reaching
# a command line.
#
# In single-agent mode (agents option is empty) this writes to the legacy env
# dir and is byte-compatible with 0.1.x.
#
# In multi-agent mode (agents option is a JSON array of per-agent override
# objects), each agent's overrides are merged over the top-level defaults via jq,
# and a separate env dir is produced per agent with its own secrets directory
# reference.
# ==============================================================================
set -e

OPTIONS_FILE=/data/options.json
SECRETS_DIR=/data/.secrets
ENV_BASE=/var/run/buzz-agent
ENV_DIR_SINGLE="${ENV_BASE}/env"

install -d -m 0700 "${ENV_BASE}"
install -d -m 0700 "${ENV_DIR_SINGLE}"

# ------------------------------------------------------------------------------
# jq helpers — every reader takes the JSON source as $1 so we can feed a
# per-agent merged config just as easily as the top-level options.
# ------------------------------------------------------------------------------

# Read a string field. jq's `//` treats false as absent, so it is only safe
# for strings; there are booleans on purpose — see _opt_bool.
_opt() {
    printf '%s' "$1" | jq -r --arg k "$2" '.[$k] // empty'
}

# Read a boolean field. Deliberately does NOT use jq's `//`, which treats
# false as absent exactly like null — with `//` a user setting the option to
# false would silently get the default. Uses has() to distinguish false from
# missing. $1 = json, $2 = key, $3 = default ("true"/"false").
_opt_bool() {
    local value
    value="$(printf '%s' "$1" | jq -r --arg k "$2" \
        'if has($k) and .[$k] != null then (.[$k] | tostring) else "" end')"
    case "${value}" in
        true | false) printf '%s' "${value}" ;;
        *) printf '%s' "$3" ;;
    esac
}

# Write a file under an env dir, mode 0600 — no secret ever reaches the process
# table or shell history.
_put_env() {
    local dir="$1" key="$2" value="$3"
    printf '%s' "${value}" > "${dir}/${key}"
    chmod 600 "${dir}/${key}"
}

# ------------------------------------------------------------------------------
# Provider env vars — shared logic, written into whichever env dir we are
# building. $1 = env_dir, $2 = json config.
# ------------------------------------------------------------------------------
_write_provider_env() {
    local env_dir="$1" json="$2"
    local provider api_key model api_base_url
    provider="$(_opt "${json}" provider)"
    [ -n "${provider}" ] || provider="openrouter"
    api_key="$(_opt "${json}" api_key)"
    model="$(_opt "${json}" model)"
    api_base_url="$(_opt "${json}" api_base_url)"

    if [ -z "${api_key}" ] && [ "${provider}" != "databricks" ]; then
        bashio::exit.nok "The 'api_key' option is required for provider '${provider}'."
    fi

    _put_env "${env_dir}" BUZZ_AGENT_PROVIDER "${provider}"
    case "${provider}" in
        openrouter)
            _put_env "${env_dir}" OPENROUTER_API_KEY "${api_key}"
            [ -n "${model}" ] && _put_env "${env_dir}" OPENROUTER_MODEL "${model}"
            ;;
        anthropic)
            _put_env "${env_dir}" ANTHROPIC_API_KEY "${api_key}"
            [ -n "${model}" ] && _put_env "${env_dir}" ANTHROPIC_MODEL "${model}"
            ;;
        openai)
            _put_env "${env_dir}" OPENAI_COMPAT_API_KEY "${api_key}"
            [ -n "${model}" ] && _put_env "${env_dir}" OPENAI_COMPAT_MODEL "${model}"
            if [ -z "${api_base_url}" ]; then
                bashio::exit.nok "Provider 'openai' needs 'api_base_url' (for example \
https://api.openai.com/v1, or your own vLLM/llama.cpp/Ollama endpoint)."
            fi
            _put_env "${env_dir}" OPENAI_COMPAT_BASE_URL "${api_base_url}"
            ;;
        databricks)
            if [ -z "${api_base_url}" ]; then
                bashio::exit.nok "Provider 'databricks' needs 'api_base_url' set to your workspace host."
            fi
            _put_env "${env_dir}" DATABRICKS_HOST "${api_base_url}"
            [ -n "${model}" ] && _put_env "${env_dir}" DATABRICKS_MODEL "${model}"
            ;;
    esac
}

# ------------------------------------------------------------------------------
# Write the complete env dir for one agent.
#   $1 = env_dir     (where files are written)
#   $2 = key_file     (path to this agent's private key)
#   $3 = home_dir     (isolated HOME for git config isolation)
#   $4 = json config  (merged top-level + per-agent overrides)
# ------------------------------------------------------------------------------
_write_agent_env() {
    local env_dir="$1" key_file="$2" home_dir="$3" json="$4"
    install -d -m 0700 "${env_dir}"

    _write_provider_env "${env_dir}" "${json}"

    # --- Relay & identity (shared across agents) --------------------------------
    _put_env "${env_dir}" BUZZ_RELAY_URL "$(_opt "${json}" relay_url)"
    _put_env "${env_dir}" BUZZ_PRIVATE_KEY "$(cat "${key_file}")"
    _put_env "${env_dir}" BUZZ_ACP_AGENT_OWNER "$(_opt "${json}" owner_pubkey)"

    # The harness defaults to spawning `goose`, which this image does not ship,
    # with an `acp` argument that only goose understands. Point it at the
    # bundled agent and clear the argument.
    _put_env "${env_dir}" BUZZ_ACP_AGENT_COMMAND "buzz-agent"
    _put_env "${env_dir}" BUZZ_ACP_AGENT_ARGS ""

    # --- MCP sidecar ----------------------------------------------------------
    # The sidecar is what gives the agent its tools; the agent answers by running
    # `buzz messages send` through its shell tool. With no sidecar,
    # build_mcp_servers() returns an empty list, the agent has no tools, and every
    # turn ends "ok" without posting. The harness passes the sidecar
    # BUZZ_RELAY_URL and the agent's key, so the CLI is authenticated.
    local mcp_command
    mcp_command="$(_opt "${json}" mcp_command)"
    [ -n "${mcp_command}" ] || mcp_command="buzz-dev-mcp"
    if [ "${mcp_command}" = "none" ]; then
        _put_env "${env_dir}" BUZZ_ACP_MCP_COMMAND ""
        bashio::log.warning "mcp_command is 'none': the agent will have no tools and cannot reply."
    else
        _put_env "${env_dir}" BUZZ_ACP_MCP_COMMAND "${mcp_command}"
    fi

    # --- Mention filter (boolean — uses has() to respect explicit false) ------
    local require_mention
    require_mention="$(_opt_bool "${json}" require_mention true)"
    if [ "${require_mention}" = "false" ]; then
        _put_env "${env_dir}" BUZZ_ACP_NO_MENTION_FILTER "true"
    fi

    # --- Conversation policy --------------------------------------------------
    local respond_to
    respond_to="$(_opt "${json}" respond_to)"
    [ -n "${respond_to}" ] || respond_to="owner-only"
    _put_env "${env_dir}" BUZZ_ACP_RESPOND_TO "${respond_to}"

    local allowlist
    allowlist="$(_opt "${json}" respond_to_allowlist)"
    if [ "${respond_to}" = "allowlist" ]; then
        if [ -z "${allowlist}" ]; then
            bashio::exit.nok "respond_to is 'allowlist' but 'respond_to_allowlist' is empty."
        fi
        _put_env "${env_dir}" BUZZ_ACP_RESPOND_TO_ALLOWLIST "${allowlist}"
    fi

    local subscribe
    subscribe="$(_opt "${json}" subscribe)"
    [ -n "${subscribe}" ] || subscribe="mentions"
    _put_env "${env_dir}" BUZZ_ACP_SUBSCRIBE "${subscribe}"

    # --- Channel access -------------------------------------------------------
    # join_channels: channels to *join* (membership). Different from channels
    # below, which only filters what an already-joined agent listens to.
    local join_channels
    join_channels="$(_opt "${json}" join_channels)"
    [ -n "${join_channels}" ] && _put_env "${env_dir}" BUZZ_AGENT_JOIN_CHANNELS "${join_channels}"

    local channels
    channels="$(_opt "${json}" channels)"
    [ -n "${channels}" ] && _put_env "${env_dir}" BUZZ_ACP_CHANNELS "${channels}"

    # --- Extra instructions ---------------------------------------------------
    local system_prompt
    system_prompt="$(_opt "${json}" system_prompt)"
    [ -n "${system_prompt}" ] && _put_env "${env_dir}" BUZZ_ACP_SYSTEM_PROMPT "${system_prompt}"

    # --- Role persona ---------------------------------------------------------
    # role is a list(agent|coding|finance|home|research|security). At the top
    # level HA Supervisor stores it as a comma-separated string; inside the
    # agents JSON array it may be a native JSON array. Normalize to a
    # comma-separated string for the env var.
    local role
    role="$(printf '%s' "${json}" | jq -r \
        '.role | if type == "array" then join(",") elif type == "string" then . else "" end')"
    if [ -n "${role}" ]; then
        _put_env "${env_dir}" BUZZ_AGENT_ROLE "${role}"
    fi

    # --- Logging --------------------------------------------------------------
    local log_level
    log_level="$(_opt "${json}" log_level)"
    [ -n "${log_level}" ] || log_level="info"
    _put_env "${env_dir}" RUST_LOG "buzz_acp=${log_level},buzz_agent=${log_level}"

    _put_env "${env_dir}" HOME "${home_dir}"

    # --- Profile fields -------------------------------------------------------
    # buzz-acp never publishes a kind:0 profile of its own, so without this the
    # agent shows up as a bare npub. The service script publishes these with
    # `buzz users set-profile` once it can reach the relay.
    local display_name
    display_name="$(_opt "${json}" display_name)"
    [ -n "${display_name}" ] && _put_env "${env_dir}" BUZZ_AGENT_DISPLAY_NAME "${display_name}"
    # Also forwarded to the bundled git tooling as the commit author name
    # instead of the raw npub.
    [ -n "${display_name}" ] && _put_env "${env_dir}" BUZZ_ACP_DISPLAY_NAME "${display_name}"

    local about
    about="$(_opt "${json}" about)"
    [ -n "${about}" ] && _put_env "${env_dir}" BUZZ_AGENT_ABOUT "${about}"

    local avatar_url
    avatar_url="$(_opt "${json}" avatar_url)"
    [ -n "${avatar_url}" ] && _put_env "${env_dir}" BUZZ_AGENT_AVATAR "${avatar_url}"

    # --- Summary log ----------------------------------------------------------
    local label
    label="$(jq -r '.display_name // "agent" // empty' <<< "${json}")"
    [ -n "${label}" ] || label="agent"
    local log_provider log_model
    log_provider="$(_opt "${json}" provider)"
    [ -n "${log_provider}" ] || log_provider="openrouter"
    log_model="$(_opt "${json}" model)"
    bashio::log.info "Agent '${label}' configured: provider=${log_provider} \
model=${log_model:-<provider default>} role=${role:-<none>} respond_to=${respond_to} \
subscribe=${subscribe} mention_required=${require_mention} tools=${mcp_command}"
}

# ------------------------------------------------------------------------------
# Shared validation — these options are always shared (all agents connect to
# the same relay and use the same LLM provider key).
# ------------------------------------------------------------------------------
OPTIONS_JSON="$(cat "${OPTIONS_FILE}")"

RELAY_URL="$(_opt "${OPTIONS_JSON}" relay_url)"
if [ -z "${RELAY_URL}" ]; then
    bashio::exit.nok "The 'relay_url' option is required. It must be exactly the same URL the \
Buzz add-on is configured with — the relay looks a community up by the host you connect to and \
has no fallback."
fi
case "${RELAY_URL}" in
    ws://* | wss://*) ;;
    *) bashio::exit.nok "relay_url must start with ws:// or wss:// (got '${RELAY_URL}')." ;;
esac

OWNER="$(_opt "${OPTIONS_JSON}" owner_pubkey)"
if [ -z "${OWNER}" ]; then
    bashio::exit.nok "The 'owner_pubkey' option is required: it is who the agent takes \
instructions from. Use the same key as the Buzz add-on's owner_pubkey."
fi

PROVIDER_SHARED="$(_opt "${OPTIONS_JSON}" provider)"
[ -n "${PROVIDER_SHARED}" ] || PROVIDER_SHARED="openrouter"
API_KEY_SHARED="$(_opt "${OPTIONS_JSON}" api_key)"
if [ -z "${API_KEY_SHARED}" ] && [ "${PROVIDER_SHARED}" != "databricks" ]; then
    bashio::exit.nok "The 'api_key' option is required for provider '${PROVIDER_SHARED}'."
fi

# ------------------------------------------------------------------------------
# Determine agent count — must match the logic in 10-agent-identity.sh.
# ------------------------------------------------------------------------------
AGENTS_JSON="$(jq -r '.agents // empty' "${OPTIONS_FILE}")"
AGENT_COUNT=0
if [ -n "${AGENTS_JSON}" ] && [ "${AGENTS_JSON}" != "[]" ]; then
    AGENT_COUNT="$(printf '%s' "${AGENTS_JSON}" | jq 'length')"
fi

# ------------------------------------------------------------------------------
# Generate env dirs
# ------------------------------------------------------------------------------
if [ "${AGENT_COUNT}" -eq 0 ]; then
    # --- Single-agent mode (backward compatible with 0.1.x) ---
    _write_agent_env "${ENV_DIR_SINGLE}" \
        "${SECRETS_DIR}/agent_private_key" \
        "/data/agent" \
        "${OPTIONS_JSON}"
    bashio::log.info "Relay: ${RELAY_URL}"
    bashio::log.info "This must match the Buzz add-on's relay_url exactly, or the relay will answer"
    bashio::log.info "'no community is configured for this host'."
else
    # --- Multi-agent mode ---
    for i in $(seq 0 $((AGENT_COUNT - 1))); do
        env_dir="${ENV_BASE}/agents/${i}/env"
        key_file="${SECRETS_DIR}/agent_${i}_private_key"
        home_dir="/data/agents/${i}/home"

        # Create the per-agent HOME directory for git config isolation
        install -d -o agent -g agent -m 0750 "${home_dir}"

        # Merge top-level options (minus the agents array) with this agent's
        # per-agent overrides. jq's `+` does a shallow merge: keys in the
        # agent object replace the top-level defaults.
        merged="$(jq --argjson i "${i}" '
            .agents = (.agents | fromjson)
            | . as $root
            | ($root | del(.agents)) as $base
            | ($base + ($root.agents[$i] // {}))
        ' "${OPTIONS_FILE}")"

        _write_agent_env "${env_dir}" "${key_file}" "${home_dir}" "${merged}"
    done
    bashio::log.info "${AGENT_COUNT} agents configured"
    bashio::log.info "Relay: ${RELAY_URL}"
    bashio::log.info "This must match the Buzz add-on's relay_url exactly, or the relay will answer"
    bashio::log.info "'no community is configured for this host'."
fi
