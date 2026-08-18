# Buzz Agent

Runs a [Buzz](https://buzz.xyz) AI agent on Home Assistant, so it stays online
when your laptop is closed. It connects to your relay as its own participant and
answers when mentioned.

This is a companion to the **Buzz** add-on in this repository, which runs the
relay itself. The agent can point at any Buzz relay, but the relay must already
exist.

## How it fits together

Buzz's own remote-agent specification says the desktop app is "one launcher
among many": an agent is any process holding a Nostr key, a relay URL and the
`buzz-acp` harness. This add-on is such a launcher. It bundles upstream's
`sprig` image contents — one static binary providing the `buzz-acp` harness, the
`buzz-agent` LLM agent, `git`, `rg` and `tree` — so there is no Node or Python
runtime and the image is ~53 MB.

## Setup

### 1. Install and configure

| Option | Notes |
| --- | --- |
| `relay_url` | **Must be byte-identical to the Buzz add-on's `relay_url`.** |
| `owner_pubkey` | Who the agent takes instructions from — normally your own key, the same one the relay has as owner. |
| `provider` | `openrouter` (default), `anthropic`, `openai` or `databricks`. Shared by all agents. |
| `api_key` | Your LLM API key. Stored as a password field. Shared by all agents. |
| `model` | e.g. `anthropic/claude-sonnet-4.5` for OpenRouter, `claude-sonnet-4-5` for Anthropic. Shared by all agents unless overridden per-agent. |
| `api_base_url` | Required for `openai` (any OpenAI-compatible endpoint) and `databricks`. |
| `agents` | **Multi-agent mode.** A JSON array string of per-agent override objects. Each object inherits the top-level options and overrides any fields it sets. Leave empty for single-agent mode (identical to 0.1.x). Example: `[{"display_name":"Coder","role":["coding"]},{"display_name":"Researcher","role":["research"]}]`. |
| `role` | `list(agent\|coding\|finance\|home\|research\|security)`. Default role(s) applied to all agents. An agent in the `agents` array may override this with its own `role`. Forwarded to the agent as `BUZZ_AGENT_ROLE`. |
| `display_name`, `about`, `avatar_url` | The profile the agent publishes, so it appears under a name rather than a bare npub. Can be overridden per-agent. |
| `respond_to` | `owner-only` (default), `anyone`, or `allowlist`. Can be overridden per-agent. |
| `respond_to_allowlist` | Comma-separated hex pubkeys, required when `respond_to` is `allowlist`. |
| `subscribe` | `mentions` (default) or `all`. |
| `require_mention` | `true` (default) means a message must tag the agent. Set `false` to answer anything said in its channels — still gated by `respond_to`. |
| `join_channels` | Channels to join at start, by name or UUID, comma-separated. Without this the agent belongs to nothing and sits idle. Can be overridden per-agent. |
| `channels` | Optional filter narrowing which of its channels it listens to. Not the same as `join_channels`. |
| `mcp_command` | Tool sidecar, default `buzz-dev-mcp`. The agent replies by running `buzz messages send` through its shell tool, so `none` leaves it unable to answer. |
| `system_prompt` | Optional extra instructions. Can be overridden per-agent. |
| `log_level` | `trace`, `debug`, `info` (default), `warn` or `error`. Note a message dropped by the mention filter logs nothing at any level. |

The `relay_url` warning is not decoration: the relay resolves a community from
the host you connect to and has **no fallback**, so a mismatch fails with
`no community is configured for this host`. If your relay is behind a tunnel at
`wss://buzz.example.com`, the agent uses that too — even though it is running on
the same machine.

### 2. Start it once and copy the public key

The agent generates its own identity on first start and prints it:

```
This agent's public key:
  b001f6ffd3d6c466352110deeb8c4992dc637172fb1318d4adeaf10697e5890d
```

On a closed relay the first start then stops with
`Auth failed: restricted: not a relay member`. That is expected — the relay has
never heard of this key yet.

### 3. Add it to the relay, then restart the agent

In the **Buzz** add-on's configuration, add that key to `members`:

```yaml
members:
  - pubkey: b001f6ffd3d6c466352110deeb8c4992dc637172fb1318d4adeaf10697e5890d
    role: member
```

Restart the Buzz add-on (its log will show the agent in the roster), then start
this add-on again. It stays connected and appears online in Buzz.

Giving the agent its **own** key rather than sharing yours is deliberate: it can
be revoked on its own by removing that one entry, and its messages are
attributable to it.

## Multiple agents

The add-on can run **several independent agents** from one instance. Each agent
gets its own Nostr identity, workspace, and configuration — useful for dedicating
one agent to a channel (e.g. a coding assistant in `#dev`) and another to a
different purpose (e.g. a home-automation assistant in `#home`).

### Configure

Set the `agents` option to a JSON array of per-agent override objects. Every
object inherits the top-level options; anything it sets overrides the default.
Shared infrastructure — `relay_url`, `owner_pubkey`, `provider`, `api_key`,
`api_base_url` — is always shared; everything else (`display_name`, `role`,
`system_prompt`, `channels`, `join_channels`, `model`, `mcp_command`, …) can be
overridden per agent.

```json
[
  {
    "display_name": "Coder",
    "role": ["coding"],
    "join_channels": "dev"
  },
  {
    "display_name": "Home Bot",
    "role": ["home"],
    "system_prompt": "You help with Home Assistant automations.",
    "join_channels": "home"
  }
]
```

The top-level `role` option is a default applied to every agent; an agent that
specifies its own `role` replaces it. Leave `agents` empty for single-agent mode
(identical to 0.1.x).

### Start and register

On first start the add-on prints each agent's public key:

```
Agent public keys:
  Agent 0: b001f6ffd3d6c466352110deeb8c4992dc637172fb1318d4adeaf10697e5890d
  Agent 1: 3a7cdef09b8e1f2c3456071829abcdeff0123456789abcdef0123456789abcdef
```

Add **every** key to the Buzz add-on's `members` list, then restart the agent
add-on:

```yaml
members:
  - pubkey: b001f6ffd3d6c466352110deeb8c4992dc637172fb1318d4adeaf10697e5890d
    role: member
  - pubkey: 3a7cdef09b8e1f2c3456071829abcdeff0123456789abcdef0123456789abcdef
    role: member
```

Each agent publishes its own profile and joins its own channels independently
at start.

### Isolation

Each agent runs in its own process with a separate private key, HOME
directory, and workspace:

| Agent | Private key | Workspace | Env dir |
| --- | --- | --- | --- |
| 0 | `/data/.secrets/agent_0_private_key` | `/data/agents/0/workspace` | `/var/run/buzz-agent/agents/0/env/` |
| 1 | `/data/.secrets/agent_1_private_key` | `/data/agents/1/workspace` | `/var/run/buzz-agent/agents/1/env/` |

Upgrading from 0.1.x auto-migrates the legacy key
(`/data/.secrets/agent_private_key`) to `agent_0_private_key`, so your existing
single agent keeps its identity without re-registration.

If any agent process exits, the supervisor tears down all agents and halts the
add-on so Home Assistant can restart it — a half-dead set of agents is worse
than a clean restart.

## Where the agent appears — and why it might look invisible

Being a relay member is not enough to see it. Two separate things matter:

**A name.** `buzz-acp` never publishes a profile of its own, so without help the
agent shows up as a bare npub. This add-on publishes one at every start from the
`display_name`, `about` and `avatar_url` options (a replaceable kind:0 event, so
re-publishing is harmless). The log confirms it:

```
Published the agent profile as 'HA Agent'
```

On the very first start this fails — the agent is not a relay member yet — and
you get a warning instead. It succeeds on the restart after you add it to
`members`.

**Channel membership.** The agent only acts in channels it belongs to.
`discover_channels` looks for NIP-29 kind:39002 member events containing the
agent's pubkey, so an agent in no channel logs this and does nothing:

```
discovered 0 channel(s)
no channel subscriptions resolved — agent will sit idle
```

That is the single most likely reason a correctly configured agent appears
broken. Set `join_channels` and it joins them itself at every start:

```yaml
join_channels: general, dev
```

Entries are channel names (resolved through the relay's channel search) or
channel UUIDs, comma-separated. Joining is idempotent, and the agent then shows
up in that channel's member list. A name that does not resolve — a private
channel it cannot see, or a typo — is logged as a warning and skipped.

Adding it from Buzz Desktop instead works just as well; restart the add-on
afterwards so discovery re-runs.

Note `join_channels` (membership) is not the same as `channels` (a filter that
narrows which of its channels an already-joined agent listens to).

## How the agent actually replies (and why it might not)

The agent does not "emit" a reply. It is told, in the harness's base prompt, that the `buzz` CLI
is its interface, and it answers by running `buzz messages send` through the **shell tool** from
its MCP sidecar. The harness hands that sidecar `BUZZ_RELAY_URL` and the agent's key, so the CLI
is already authenticated.

That means **an agent with no MCP sidecar is silent by construction**: it receives your message,
calls the model, produces an answer, and has no way to post it. The turn ends `outcome="ok"` with
nothing in the channel. The `mcp_command` option defaults to `buzz-dev-mcp` for exactly this
reason; setting it to `none` disables tools and the agent will not be able to reply.

Signals worth knowing when it goes quiet:

| What you see | Meaning |
| --- | --- |
| `⚠️ I couldn't process the last request…` in the channel | The turn ran and the **model** failed. Check the provider and the model. |
| `agent_returned … outcome="ok"` in the log, nothing in the channel | The model answered but could not post — check `mcp_command`. |
| No log line at all when you post | The message never matched: not in a channel it belongs to, or no `p` tag (see `require_mention`). |

Note that a filtered-out message logs **nothing at any level**, including `debug`, so silence in
the log is not evidence that the message failed to arrive.

## Talking to it

Mention the agent in a channel from Desktop or mobile. With the defaults
(`subscribe: mentions`, `respond_to: owner-only`) it only reacts when mentioned,
and only to you.

## What the agent can touch

The add-on maps **nothing** from Home Assistant — no `/config`, no `/share`, no
`/media`. The agent works in `/data/workspace` inside its own container, with
`HOME=/data/agent`. Its tools (shell, file edits, git) are confined there.

It does have full network access, which is unavoidable: it has to reach your
relay and your LLM provider. Treat the API key as spendable money and keep
`respond_to: owner-only` unless you have a reason not to.

## Cost

An always-on agent bills tokens whenever it is mentioned. There is no spend cap
in this add-on. `respond_to: owner-only` plus an explicit `channels` list are the
guards available; the provider's own usage limits are the real backstop.

## Backups

`/data/.secrets/agent_private_key` (0.1.x) or `/data/.secrets/agent_<i>_private_key`
(multi-agent) is the agent's identity. Losing it means generating a new one and
re-adding it to the relay — annoying but not fatal, and nothing else in `/data`
is precious. The add-on is marked `backup: cold`.

## Troubleshooting

**`Auth failed: restricted: not a relay member`** — the pubkey is not in the
relay's roster yet. See step 3. The add-on stops on this rather than retrying,
because it is a terminal error, not a blip; restart it after adding the member.

**`no community is configured for this host`** — `relay_url` does not match the
Buzz add-on's `relay_url` exactly.

**`BUZZ_AGENT_PROVIDER is required`** — the provider mapping did not produce a
key; check `api_key` is set.

**The agent starts, then nothing happens when mentioned** — check `respond_to`
(default is owner-only, so only `owner_pubkey` gets replies) and `channels` if
you set it.

## Notes

- The upstream image is pinned by tag in the `Dockerfile` and bumped
  deliberately with the add-on version.
- Multiple agents can run in a single add-on instance via the `agents` option;
  each gets its own key, workspace, and process.
- MCP servers other than the bundled `buzz-dev-mcp` are not wired up yet.

---

Unofficial community add-on, not affiliated with Block, Inc. Buzz is Apache-2.0;
the Buzz name and logo are Block's.
