# Buzz Agent

Runs a [Buzz](https://buzz.xyz) AI agent on Home Assistant, so it stays online when your laptop is
closed.

Buzz Desktop can run agents, but they die with the machine that launched them. Upstream's own
specification is explicit that the desktop is "one launcher among many" — an agent is any process
holding a Nostr key, a relay URL and the `buzz-acp` harness. This add-on is that launcher, built
from upstream's `sprig` runtime: a single static binary providing the harness, the `buzz-agent`
LLM agent, its tool sidecar, git, `rg` and `tree`. No Node, no Python, about 53 MB.

The agent generates **its own identity** on first start and prints the public key for you to add
to the relay's member list, so it is revocable on its own rather than borrowing yours. It works
with OpenRouter, Anthropic, any OpenAI-compatible endpoint, or Databricks.

Sandboxed by default: nothing from Home Assistant is mounted in, so its shell and file tools stay
inside its own workspace.

Needs a Buzz relay to connect to — the **Buzz** add-on in this repository, or any other. See the
Documentation tab for setup, channel joining and troubleshooting.

---

Unofficial community add-on, not affiliated with Block, Inc. Buzz is Apache-2.0; the Buzz name and
logo are Block's.
