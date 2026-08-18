# Home Assistant add-ons

A small collection of Home Assistant add-ons, mostly things I wanted running on my own hardware
rather than someone else's.

[![Open your Home Assistant instance and show the add add-on repository dialog with a specific repository URL pre-filled.](https://my.home-assistant.io/badges/supervisor_add_addon_repository.svg)](https://my.home-assistant.io/redirect/supervisor_add_addon_repository/?repository_url=https%3A%2F%2Fgithub.com%2FLauR3y%2Fhassio-addons)

Or add it manually: **Settings → Add-ons → Add-on Store → ⋮ → Repositories**, then paste
`https://github.com/LauR3y/hassio-addons`.

## Add-ons

| Add-on | Version | Architectures | What it does |
| --- | --- | --- | --- |
| [**Buzz**](buzz) | 0.1.7 | aarch64, amd64 | Self-hosted [Buzz](https://buzz.xyz) relay — the server for Block's workspace for humans and AI agents, with PostgreSQL, Redis and MinIO bundled in one add-on. |
| [**Buzz Agent**](buzz-agent) | 0.2.0 | aarch64, amd64 | One or more Buzz AI agents that stay online on your HA box instead of dying with your laptop. |
| [**Wealthfolio**](wealthfolio) | 0.1.0 | aarch64, amd64 | Self-hosted [Wealthfolio](https://wealthfolio.app) portfolio and finance tracker. |
| [**Aider**](aider) | 0.2.3 | aarch64, amd64 | [Aider](https://aider.chat) AI pair programming in a browser terminal, via ingress. |
| [**SBFspot**](sbfspot) | 0.0.18 | armhf, armv7, aarch64, amd64, i386 | Reads SMA solar inverters over Bluetooth/Speedwire into MySQL and PVoutput. |
| [**Surveillance stream**](surveillancestream) | 0.0.40 | armv7, amd64 | Web UI for surveillance camera streams. |

Every add-on is built by the Supervisor on your own device — nothing here is a prebuilt image
pulled from a registry I control.

## Notes

- **Buzz** and **Buzz Agent** wrap upstream software that is in early beta and pinned to specific
  upstream builds, so they are marked experimental. Read each add-on's Documentation tab before
  installing; the Buzz relay in particular keys its community on the exact URL clients use, which
  is worth understanding up front.
- Issues and pull requests welcome, though these exist primarily to scratch my own itches.

## License

Add-on packaging in this repository is provided as-is. Each add-on wraps upstream software under
its own license — Buzz is Apache-2.0, and the Buzz name and logo belong to Block, Inc. These are
unofficial community add-ons with no affiliation to the upstream projects.
