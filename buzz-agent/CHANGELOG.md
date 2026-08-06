# Changelog

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
