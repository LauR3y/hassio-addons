# Wealthfolio

Self-hosted portfolio & finance tracker — see https://wealthfolio.app.

## Quick start

1. Set the **password** option (this is your login password — the add-on hashes
   it with argon2id before passing it to Wealthfolio).
2. (Optional) Set **cors_allow_origins** to the URL you'll use to access the
   add-on. Defaults to `http://homeassistant.local:8088`. Required because
   Wealthfolio refuses `*` when authentication is enabled.
3. Start the add-on, then click **Open Web UI**.

## Adding a sidebar entry

Wealthfolio's frontend is a Vite SPA with assets pinned to root-path serving, so
HA ingress can't proxy it without breaking lazy-loaded routes. The next-best
option is `panel_iframe`, which adds a sidebar entry that opens a URL inside an
HA iframe. Add this to your `configuration.yaml`:

```yaml
panel_iframe:
  wealthfolio:
    title: Wealthfolio
    icon: mdi:chart-line
    url: "http://homeassistant.local:8088"
    require_admin: true
```

Then **Developer Tools → YAML → Reload Frontend** (or restart HA). A
**Wealthfolio** entry appears in the sidebar.

Replace the URL if your HA instance uses a different hostname or IP.

### Mixed content

If you access HA over HTTPS, browsers will refuse to load an HTTP iframe. Two
options:

- Use the **Open Web UI** button on the add-on page (opens in a new tab — no
  mixed-content rule).
- Front the add-on with a TLS-terminating reverse proxy (e.g. NGINX Proxy
  Manager) and point `panel_iframe.url` at the HTTPS URL. Update the
  `cors_allow_origins` option to that HTTPS URL too.

## Persistence

The add-on persists the following inside the HA add-on data volume (`/data`):

- `secret.key` — auto-generated 32-byte `WF_SECRET_KEY` (override via the
  `secret_key` option).
- `auth.salt` — argon2 salt; persisted so the password hash stays stable.
- `wealthfolio.db` — SQLite database with your portfolio data.
- `secrets.json` — Wealthfolio's encrypted secrets store.

If you uninstall the add-on, HA wipes this volume. Back up
`/addons/data/<slug>/` on the host beforehand if you want to keep your data.
