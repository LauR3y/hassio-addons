# Changelog

## 0.1.6

- Add an add-on icon and logo, and a README so the store shows a description
  instead of a blank tile.
- Mark the add-on `experimental`: it pins an upstream `main`-branch snapshot of
  software that is itself in early beta.
- Drop the `panel_icon`/`panel_title` keys — they configure the sidebar panel an
  ingress add-on gets, and this add-on has no ingress, so nothing rendered them.

## 0.1.5

- Add the bundled NIP-AB device pairing relay, so Buzz Desktop's *Settings →
  Mobile* QR pairing works. The main relay does not serve `/pair`, and without a
  pairing relay advertised in NIP-11 Desktop fell back to that legacy path and
  failed with `WebSocket connection failed: HTTP error: 404 Not Found`.
  Opt in with the new `pairing_relay_url` option and publish port 5000; left
  empty, nothing changes and pairing stays off.
- Document invites as the simpler way to add a phone: the phone joins with its
  own identity and is added as a member automatically, with no pairing relay and
  no add-on configuration.

## 0.1.4

- Remove the "Open Web UI" button. Home Assistant substitutes `[HOST]` with the
  host you are browsing HA on, so the button opened the wrong address — through
  a Cloudflare tunnel it produced `http://<your-ha-domain>:3000/`, which is not
  published, and on a LAN it opened the HA hostname rather than the `relay_url`
  host. The add-on already logs the correct URL at every start.
- Document remote access through a Cloudflare tunnel, including the order of
  operations (close the relay *before* the public hostname goes live) and the
  Cloudflare limits that matter for git pushes and media uploads.
- Document that the web bundle lists git repositories only, and is empty until
  a repository is pushed from Buzz Desktop.

## 0.1.3

- Fix boolean options set to `false` being silently ignored. Options were read
  with `jq '.[$k] // empty'`, and jq treats `false` as falsy, so
  `require_relay_membership: false` and `serve_web_gui: false` collapsed to
  their defaults and never reached the relay.
- Log whether the relay ended up open or closed, since that failure was
  invisible.

## 0.1.2

- Log the relay roster at every start, so the pubkeys allowed to connect appear
  next to any "not a relay member" rejection in the same log.
- Warn when `relay_url` uses a `.local` name: mDNS commonly resolves to IPv6
  first, Buzz Desktop's HTTP client does not fall back, and the add-on's port is
  published over IPv4 only — which shows up as
  `join policy request failed: error sending request`.
- Document the join failures, the invite flow, and how the browser UI behaves on
  a closed relay.

## 0.1.1

- Fix first boot on a real filesystem: `initdb` runs as the `postgres` user and
  could not read the generated password, which lives in a root-only directory.
  The password is now staged in a postgres-owned file for the duration of
  `initdb` and removed afterwards, so `/data/.secrets` stays root-only.
- Ensure `/data` is traversable by the service users, and clear a partially
  initialised cluster so a failed `initdb` can be retried.

## 0.1.0

- Initial release: Buzz relay with bundled PostgreSQL 17, Redis and MinIO in a
  single add-on, all state under `/data`.
