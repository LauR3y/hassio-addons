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
| `provider` | `openrouter` (default), `anthropic`, `openai` or `databricks`. |
| `api_key` | Your LLM API key. Stored as a password field. |
| `model` | e.g. `anthropic/claude-sonnet-4.5` for OpenRouter, `claude-sonnet-4-5` for Anthropic. |
| `api_base_url` | Required for `openai` (any OpenAI-compatible endpoint) and `databricks`. |
| `respond_to` | `owner-only` (default), `anyone`, or `allowlist`. |
| `subscribe` | `mentions` (default) or `all`. |
| `channels` | Optional comma-separated channel IDs to limit the agent to. |
| `system_prompt` | Optional extra instructions. |

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

**Channel membership.** The agent only acts in channels it has been *added to*.
`discover_channels` looks for NIP-29 kind:39002 member events containing the
agent's pubkey, so until you add it to a channel in Buzz, the log says:

```
discovered 0 channel(s)
no channel subscriptions resolved — agent will sit idle
```

That is the single most likely reason a correctly configured agent appears to do
nothing. Add it to a channel from Desktop, then restart this add-on so it
re-runs discovery.

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

`/data/.secrets/agent_private_key` is the agent's identity. Losing it means
generating a new one and re-adding it to the relay — annoying but not fatal, and
nothing else in `/data` is precious. The add-on is marked `backup: cold`.

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
- One agent per add-on instance. A second agent means a second copy of this
  directory with its own slug.
- MCP servers other than the bundled `buzz-dev-mcp` are not wired up yet.
