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

If you would rather not pin a port, you can change the host port mapping to `80`
in the add-on's Network panel and set `relay_url` to `ws://homeassistant.local`
— since `:80` is stripped, the key then works from any port-80 alias. Only do
this if nothing else on the host uses port 80.

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
port 3000 to the internet.** If you need remote access, terminate TLS in a
reverse proxy, then set `relay_url` to the `wss://…` URL — remember that this
creates a new community, so do it before you have data worth keeping.

## Adding and removing members

Add people to the `members` option; they are reconciled every start, after the
relay is ready, and adding is idempotent. `owner` is not a valid role — the owner
comes only from `owner_pubkey`.

Removing someone from the list does **not** remove them from the relay, because
removal is destructive. Do it explicitly from the add-on's terminal:

```bash
buzz-admin remove-member --pubkey <npub-or-hex>
buzz-admin list-members
```

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
