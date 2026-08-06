# Buzz

Runs a self-hosted [Buzz](https://buzz.xyz) relay on Home Assistant. Buzz is
Block's open-source workspace for humans and AI agents
([block/buzz](https://github.com/block/buzz), Apache-2.0).

## What this add-on is (and is not)

This add-on runs the Buzz **server** (the relay): the Nostr relay, the REST API,
media storage and git-over-object-storage. Upstream ships this as a five-service
`docker compose` stack; because Home Assistant runs one container per add-on,
this bundles all of it — relay, PostgreSQL 17, Redis and MinIO — into a single
add-on with every piece of state under `/data`.

**You still need a Buzz client.** Chat, DMs and canvases live in **Buzz Desktop**
or `buzz-cli`, pointed at your relay. The "Open Web UI" button opens the relay's
own web bundle, which is a **git repository browser** plus the `/invite/<code>`
landing page others use to join — it is not a chat UI. That is upstream's
design, not a limitation of this add-on.

Note that the web bundle **cannot authenticate on a closed relay**. Without a
NIP-07 browser extension it signs with a throwaway key that is regenerated on
every page load, so each visit is rejected with `not a relay member` in the log
and the page shows "This community is empty". That is expected. Install a NIP-07
extension and import the same key if you want the browser to work; otherwise
just use Desktop and ignore those log lines.

Even once it authenticates, that page lists **git repositories** and nothing
else. It subscribes to `{"kinds":[30617]}` (repository announcements); an
immediate `EOSE` with no events — and therefore "This community is empty" — is
the correct rendering until you push a repository from Desktop.

**There is deliberately no "Open Web UI" button.** Home Assistant substitutes
`[HOST]` in that link with whatever host you are browsing HA on, which is not
necessarily the `relay_url` host — behind a reverse proxy or tunnel it is
guaranteed to be wrong. The add-on logs the correct URL at every start instead.

## Before you start

1. Install Buzz Desktop and let it create your identity.
2. Go to **Settings → Identity → Public key** and copy it. Prefer the
   64-character hex form; an `npub1…` string also works.
3. That value goes into the `owner_pubkey` option. The owner cannot be removed
   from the relay later except by changing this option.

## Options

| Option | Default | Notes |
| --- | --- | --- |
| `relay_url` | `ws://homeassistant.local:3000` | The exact URL clients will use. **Read the warning below.** |
| `owner_pubkey` | _(required)_ | Your public key, 64-hex or `npub1…`. |
| `members` | `[]` | Additional members: `pubkey` plus `role` (`member` or `admin`). |
| `require_relay_membership` | `true` | Closed relay: only the owner and listed members may connect. |
| `serve_web_gui` | `true` | Serve the git repo browser and invite pages over HTTP. |
| `extra_cors_origins` | _(empty)_ | Comma-separated extra browser origins. |
| `log_level` | `info` | `trace`, `debug`, `info`, `warn` or `error`. |

Every secret this deployment needs — the relay identity key, the git hook HMAC
secret, and the PostgreSQL, Redis and MinIO credentials — is generated on first
start and persisted under `/data/.secrets/`. There is nothing to type.

## `relay_url` is the community's identity — set it once

Buzz keys its community on the **exact** scheme, host and port of `relay_url`.
Only `:80` and `:443` are stripped, so `ws://homeassistant.local:3000` and
`ws://homeassistant.local` are different keys, and so are the hostname and the
IP address of the same machine.

Two consequences:

- **Clients must always connect using exactly this URL.** If `relay_url` says
  `homeassistant.local:3000`, connecting to `192.168.1.50:3000` is rejected.
  Pick the name that is stable on your network and use it everywhere.
- **Changing `relay_url` later creates a second, empty community.** Your existing
  channels, members and repositories stay attached to the old URL and become
  invisible. The add-on logs a loud warning when it detects a change; setting the
  option back restores the original workspace.

**Prefer the IPv4 address over `homeassistant.local`.** Buzz Desktop resolves
the URL with a Rust HTTP client that takes the first address DNS returns and
does not fall back. `.local` names are answered by mDNS, which commonly returns
an IPv6 address first — and this add-on publishes its port through Docker, which
is IPv4-only. The result is that a browser can open the page fine (browsers
retry over IPv4) while Desktop fails with:

```
join policy request failed: error sending request for url
(http://homeassistant.local:3000/api/join-policy)
```

So set `relay_url` to the IPv4 address of your Home Assistant host, for example
`ws://192.168.1.50:3000`, and give that host a DHCP reservation in your router
so the address never changes. The add-on logs a warning if you use a `.local`
name. To check which way a name resolves:

```bash
curl -sS -o /dev/null -w '%{http_code} %{remote_ip}\n' http://homeassistant.local:3000/api/join-policy
curl -sS -4 -o /dev/null -w '%{http_code} %{remote_ip}\n' http://homeassistant.local:3000/api/join-policy
```

If the first fails and the second returns `200`, you have hit exactly this.

If you would rather not pin a port, you can change the host port mapping to `80`
in the add-on's Network panel and set `relay_url` accordingly — since `:80` is
stripped, the key then works from any port-80 alias. Only do this if nothing
else on the host uses port 80.

## First start

Expect **several minutes** on a Raspberry Pi. In order, the add-on initialises
the PostgreSQL cluster, formats the MinIO volume, runs the database migrations,
and runs a one-time MinIO conditional-write conformance probe — all before the
relay opens its port.

Leave the add-on **Watchdog off** for the first start (it would restart the
container mid-migration), then enable it afterwards if you want it.

A healthy first start logs, roughly in order:

```
Generated and persisted postgres_password
Generated this relay's identity key.
Relay owner pubkey (hex): <your key>
First boot: initialising the PostgreSQL 17 cluster in /data/postgres
Starting MinIO on 127.0.0.1:9000 (data: /data/minio)
Running the MinIO conditional-write conformance probe (once per MinIO release)
Starting buzz-relay on 0.0.0.0:3000 (relay_url=ws://homeassistant.local:3000)
Relay is ready; the community for ws://homeassistant.local:3000 exists.
Member ready: npub1... (member)
```

## Connecting

In Buzz Desktop choose **Join a Community** and enter your `relay_url`
(`ws://homeassistant.local:3000`). `buzz-cli` uses the same URL via
`BUZZ_RELAY_URL`.

This is plain, unencrypted `ws://` on your local network. **Do not port-forward
port 3000 to the internet.** If you need remote access, put it behind something
that terminates TLS — see the next section.

## Remote access with a Cloudflare tunnel

Give Buzz its **own** hostname; do not try to reuse the Home Assistant one, as
the tunnel only serves 443 for that name and the relay is on 3000.

Do these in order — the second step publishes the relay to the internet, so the
relay must be closed before it happens.

1. **Close the relay.** Set `require_relay_membership: true`, restart, and check
   the log says `Closed relay: only the owner and listed members may connect.`
   An open relay on a public hostname lets anyone on the internet join, read and
   post.
2. **Add the hostname to the tunnel.** With the Cloudflared add-on:

   ```yaml
   additional_hosts:
     - hostname: buzz.example.com
       service: http://<home-assistant-ip>:3000
   ```

   Or add the equivalent Public Hostname in the Cloudflare Zero Trust dashboard.
   Keep the add-on's `3000/tcp` port published — that is what cloudflared
   connects to. Do **not** put Cloudflare Access in front: Buzz Desktop's
   WebSocket client cannot complete an Access login, and NIP-42 membership is
   already the access control.
3. **Point the add-on at it:** `relay_url: wss://buzz.example.com` (no port, no
   trailing slash), then restart. `BUZZ_MEDIA_BASE_URL` and the CORS origin are
   derived for you. Re-join from Desktop with that exact URL.

Because `normalize_host` strips `:443`, the community key is just
`buzz.example.com` with no port to keep in sync — one fewer thing to get wrong
than a `host:3000` key.

Remember this **re-keys the community** (see the `relay_url` warning above), so
do it before you have data worth keeping.

Two Cloudflare limits worth knowing: free-plan request bodies are capped at
100 MB, which sits above this add-on's git pack limit (64 MB) and image limit
(50 MB), so pushes and uploads fit; and Cloudflare drops idle WebSocket
connections, so occasional Desktop reconnects are normal rather than a relay
fault.

## Adding and removing members

The usual way to add someone is an **invite**: from Desktop, as owner or admin,
mint an invite link. Claiming it adds that person to the relay automatically with
role `member` — no add-on configuration needed. Claiming an invite in a browser
requires a NIP-07 extension. Invite links (`/invite/<code>`) are served even when
`serve_web_gui` is off.

For keys you already know, the `members` option is the declarative alternative:
entries are reconciled on every start, after the relay is ready, and adding is
idempotent. `owner` is not a valid role — the owner comes only from
`owner_pubkey`.

Every start also logs the current roster, so you can always see which pubkeys are
allowed to connect:

```
Relay roster — only these pubkeys may connect:
  owner  e42e957c42fb5e35935041b02fa3d689a4c24ac464588aa3195ecdf0334ba797
  member 48345cda9b93a4f5926590ef20f69cd82ac2cfedb40ae56b3ade2c294a38cf16
```

Removing someone from the list does **not** remove them from the relay, because
removal is destructive. Add-ons have no built-in shell, so do it from the SSH
add-on (protection mode off), against the add-on's container:

```bash
docker exec addon_caf98a7f_buzz buzz-admin list-members
docker exec addon_caf98a7f_buzz buzz-admin remove-member --pubkey <npub-or-hex>
```

The container name is `addon_<repository-hash>_buzz`; find yours with
`docker ps --format '{{.Names}}' | grep buzz`.

## Adding a phone

Two different things, for two different goals.

**Invite (recommended).** From Desktop as owner or admin, create an invite and open
the link on the phone. The phone joins with its **own** identity and the relay
adds it as a `member` automatically, so the relay stays closed and you can
revoke that one device later. Nothing to configure in the add-on.

**Pairing** copies your *desktop identity* onto the phone, so both devices are
the same Nostr key. It uses NIP-AB: a QR code, an end-to-end encrypted channel
and a 6-digit verification code. This needs a separate pairing relay — the main
relay does not serve one — so Desktop's *Settings → Mobile* fails with
`WebSocket connection failed: HTTP error: 404 Not Found` until you set
`pairing_relay_url`.

To enable it, publish port `5000` in the add-on's Network panel and set:

```yaml
pairing_relay_url: ws://192.168.1.50:5000     # your HA host's LAN address
```

The add-on then runs the bundled `buzz-pair-relay` on that port and advertises
the URL in its NIP-11 document, which is where Desktop looks. The URL must be
reachable from **both** the desktop and the phone, which is why it is not
derived automatically: over the LAN use the host's IP; for pairing from outside,
give it its own tunnel hostname (e.g. `wss://pair.example.com` → port 5000) and
use that instead.

The pairing relay only ever sees ciphertext addressed to throwaway keys — the
payload is encrypted between the two devices and confirmed with the on-screen
code — so `wss://pairing.buzz.xyz` also works if you would rather not run one.
That does route your (encrypted) key material through a third party, which is
why this add-on does not use it by default.

## Backups

This add-on is marked `backup: cold`, so Home Assistant stops it while making a
backup — that is what makes the PostgreSQL and MinIO snapshots consistent.

In priority order, what matters:

1. **`/data/.secrets/relay_private_key`** — the relay's Nostr identity. It is
   published in the relay's NIP-11 document and signs the membership roster.
   Irreplaceable: a new key means a different relay.
2. `/data/postgres` — messages, channels, members, workflows.
3. `/data/minio` — uploaded media and git objects.
4. `/data/git` — the bare git repositories.
5. The rest of `/data/.secrets/` — database, Redis and MinIO credentials.

Uninstalling the add-on deletes `/data` and everything above.

## Hardware, memory and storage

Upstream recommends 2 vCPU and 4 GB RAM for the relay stack. Tuned as shipped
here it is much lighter than that: measured on an idle aarch64 container just
after start, the whole add-on uses **~130 MB** — MinIO ~130 MB RSS, the relay
~27 MB, Redis ~19 MB, and the PostgreSQL backends sharing 96 MB of buffers.
Expect a few hundred MB in steady use as PostgreSQL fills its shared buffers and
MinIO caches objects, and more during media uploads.

So a **4 GB Pi is fine** for a small community alongside Home Assistant (which
itself typically uses 1–1.5 GB); 8 GB gives comfortable headroom. `aarch64` and
`amd64` only — upstream publishes no 32-bit builds.

**Move the Home Assistant data disk to an SSD or NVMe before real use**
(*Settings → System → Storage → Move datadisk*). PostgreSQL's WAL and MinIO's
per-object metadata write continuously, which wears SD cards out. This add-on
already reduces that as far as it sensibly can: Redis persistence is disabled
(PostgreSQL is canonical and Redis is only pub/sub here), WAL is compressed with
15-minute checkpoints, and the disposable git pack cache is kept off `/data` and
capped at 256 MB.

The on-device build downloads roughly 200 MB of upstream layers and produces a
~1 GB image; allow ~1.5 GB free disk and 10–25 minutes on a Pi.

## Upgrading

The upstream relay image is pinned by digest tag (`ghcr.io/block/buzz:sha-…`) in
the `Dockerfile` and bumped deliberately along with the add-on version. Buzz is
in early beta and moves fast, so **back up before bumping**. Database migrations
run automatically on start.

## Notes and caveats

- **MinIO** is bundled at the release upstream's own compose stack pins. MinIO's
  community edition is now archived and AGPL-3.0 licensed, so it will not receive
  future fixes. There is no drop-in replacement today: Buzz requires S3
  conditional writes (`If-Match`/`If-None-Match` with real ETags), which the
  common lightweight S3 servers do not implement reliably.
- The relay's health endpoint (8080) and Prometheus metrics (9102) are
  deliberately **not** published; the metrics endpoint is unauthenticated.
- Home Assistant Ingress is not used: it rewrites the `Host` header and adds a
  path prefix, both of which break the relay's host-keyed community lookup.

## Troubleshooting

**Desktop: `join policy request failed: error sending request for url (…)`.**
A connection-level failure, not an HTTP error — Desktop could not reach the relay
at all. Almost always the mDNS/IPv6 trap described under `relay_url` above: use
the IPv4 address instead of `homeassistant.local`.

**Desktop: `relay returned 404 Not Found: relay: no community is configured for
this host`.** The URL you typed in Desktop does not match the add-on's
`relay_url`, and the relay refuses to guess — it has no fallback community. The
relay creates the community for `relay_url` **at startup**, so change the option
in the add-on's Configuration to exactly the URL clients will use, then
**restart** the add-on. Confirm with the log lines
`Configuration ready (relay_url=…, community host=…)` and
`Deployment community ensured host=…`.

**`not a relay member` / `relay_membership_required` in the log.** The relay
prints the rejected pubkey and the add-on prints the roster at every start;
compare the two. If the rejected pubkey is yours, put it in `owner_pubkey` or
`members` and restart. **If it changes on every attempt, it is the browser** —
the web UI signs with a throwaway key that is regenerated on each page load, so
on a closed relay it is always rejected. That is upstream behaviour, harmless,
and the reason to use Buzz Desktop rather than the browser.

**Add-on stops right after start.** Almost always a rejected `owner_pubkey` with
`require_relay_membership: true`. The log names the offending option.

**`PostgreSQL did not accept connections…`** The cluster failed to start; the
`postgres` log lines above the error say why. If `/data/postgres` is corrupt,
restore a backup — deleting it re-initialises the cluster and destroys all data.

**`MinIO did not report /minio/health/live…`** Usually slow first-time formatting
on an SD card. If it persists, the storage is too slow or too full.

**Browser errors about CORS** when opening the web UI at an address other than
`relay_url`: add that origin to `extra_cors_origins`.

**`RELAY_URL host … is not mapped to a community`** from a manual `buzz-admin`
command means the relay has not finished starting yet. Wait and retry.
