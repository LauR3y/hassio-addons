# Changelog

## 0.2.0

### Multiple agents per add-on instance

A single Buzz Agent add-on can now run **multiple independent agents**, each
with its own Nostr identity, workspace, and configuration overrides. The
`agents` option accepts a JSON array of per-agent override objects; each object
inherits the top-level options and overrides any fields it sets. When `agents`
is empty, the add-on behaves identically to 0.1.x — one agent from the
top-level options.

- New `agents` option (JSON array string): per-agent overrides for `display_name`,
  `about`, `avatar_url`, `system_prompt`, `role`, `model`, `provider`,
  `respond_to`, `channels`, `join_channels`, `mcp_command`, `log_level` and more.
- New `role` option (`list(agent|coding|finance|home|research|security)`):
  assigns a persona role to the agent(s). The top-level value is a default for
  all agents; each agent may override it. Roles are forwarded to the agent as
  `BUZZ_AGENT_ROLE`.
- Each agent gets its own private key (`/data/.secrets/agent_<i>_private_key`),
  public key (`/data/agents/<i>_pubkey`), env dir
  (`/var/run/buzz-agent/agents/<i>/env/`), HOME
  (`/data/agents/<i>/home`) and workspace
  (`/data/agents/<i>/workspace`).
- The legacy single-agent key (`/data/.secrets/agent_private_key`) is
  auto-migrated to `agent_0_private_key` on first start after upgrade.
- `services.d/agents/run` replaces `services.d/agent/`: it launches one
  `buzz-acp` per agent, fans SIGTERM to all children on shutdown, and halts
  the add-on if any agent exits.
- The `20-agent-config.sh` init script merges per-agent overrides over the
  top-level defaults via `jq`, using `has()` (not `//`) so that boolean options
  set to `false` are preserved rather than collapsed to the default.

## 0.1.4

- Add an add-on icon and logo, and a README so the store shows a description.
  The icon carries a bolt badge so it is distinguishable from the Buzz relay
  add-on at a glance.
- Mark the add-on `experimental`, matching the upstream beta it wraps.

## 0.1.3

- **Fix: the agent could never reply.** It answers by running `buzz messages send` through the
  shell tool of its MCP sidecar, and the add-on never set `BUZZ_ACP_MCP_COMMAND` — so
  `build_mcp_servers()` returned an empty list, the agent had no tools at all, and every turn
  finished `outcome="ok"` in silence while still billing the model. Now defaults to
  `buzz-dev-mcp`, configurable via the new `mcp_command` option.
- Add `require_mention` (default `true`). Setting it to `false` drops the requirement that a
  message carry a `p` tag naming the agent, so anything said in its channels triggers a turn —
  still gated by `respond_to`.
- Log the tool sidecar and mention requirement at start; both failure modes were previously
  invisible.

## 0.1.2

- Add `join_channels`: the agent joins the listed channels (by name or UUID) at
  every start. Without channel membership the harness discovers nothing and sits
  idle, which was the last manual step in getting an agent working.

## 0.1.1

- Publish the agent's profile (`display_name`, `about`, `avatar_url`) at start,
  so it appears in Buzz under a name instead of a bare npub and shows up in
  mention autocomplete. `buzz-acp` publishes no profile of its own; the
  `BUZZ_ACP_DISPLAY_NAME` variable it does read only sets the git author name.
- Log that the agent only acts in channels it has been added to — the usual
  reason a working agent seems to do nothing.

## 0.1.0

- Initial release: runs a Buzz AI agent on Home Assistant so it stays online
  when your laptop is not.
- Bundles upstream's `sprig` runtime (one static binary providing the
  `buzz-acp` harness, the `buzz-agent` LLM agent, git, rg and tree) on the
  Alpine add-on base — no Node or Python, ~53 MB.
- Generates its own Nostr identity on first start and prints the public key, so
  it can be added to the relay as a member and revoked independently rather than
  reusing the owner's key.
- Providers: OpenRouter (default), Anthropic, any OpenAI-compatible endpoint,
  and Databricks.
- Sandboxed: nothing from Home Assistant is mapped in; the agent works in
  `/data/workspace`.
