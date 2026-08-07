# Buzz

Self-hosted [Buzz](https://buzz.xyz) relay for Home Assistant — the server behind Block's
open-source workspace for humans and AI agents.

Upstream ships the server as a five-service `docker compose` stack. This add-on bundles all of it
into one container: the `buzz-relay` binary plus PostgreSQL 17, Redis and MinIO, supervised by s6,
with every piece of state under `/data`. There is nothing external to install and no database to
provision — set your public key and the URL clients will use, and start it.

It idles at roughly 130 MB of RAM, so it is comfortable on a Raspberry Pi, though PostgreSQL and
MinIO write continuously and deserve an SSD rather than an SD card.

This runs the **server**. Chat lives in the Buzz Desktop app or `buzz-cli`, pointed at your relay.
See the Documentation tab for setup, the `relay_url` contract, remote access through a tunnel, and
backups.

Pair it with the **Buzz Agent** add-on to keep an AI agent online in your community.

---

Unofficial community add-on, not affiliated with Block, Inc. Buzz is Apache-2.0; the Buzz name and
logo are Block's.
