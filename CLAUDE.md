# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Home Assistant Add-ons repository containing custom add-ons packaged as Docker containers. Each subdirectory (e.g., `sbfspot/`, `surveillancestream/`) is an independent add-on.

Current add-ons: `buzz` (Buzz relay + bundled PostgreSQL/Redis/MinIO), `buzz-agent` (a Buzz AI agent), `wealthfolio`, `aider`, `sbfspot`, `surveillancestream`. There is no CI — the Supervisor builds every add-on locally on the device, so no `image:` key is used anywhere.

## Build Commands

### Building Add-ons Locally

```bash
# Build SBFspot add-on (replace BASE_IMAGE with appropriate architecture)
docker build --build-arg BUILD_FROM=ghcr.io/hassio-addons/base/amd64:latest sbfspot/

# Build Surveillancestream add-on
docker build --build-arg BUILD_FROM=ghcr.io/hassio-addons/base/amd64:latest surveillancestream/
```

Build arguments:
- `BUILD_FROM`: Base image (required)
- `BUILD_ARCH`: Target architecture (armhf, armv7, aarch64, amd64, i386)
- `BUILD_DATE`, `BUILD_REF`, `BUILD_VERSION`: Optional metadata

## Architecture

### Add-on Structure

Each add-on follows the standard Home Assistant add-on format:
- `config.json`: Add-on metadata, options schema, and defaults. The `options` section provides default values; `schema` defines validation types.
- `Dockerfile`: Multi-arch Docker build using Home Assistant base images
- `run.sh` or `rootfs/`: Startup logic and runtime files

### SBFspot Add-on (`sbfspot/`)

Solar inverter monitoring tool (SMA inverters via Bluetooth/Speedwire):
- **Build**: C/C++ compiled with `make mysql` during Docker build
- **Runtime**: Cron-based scheduling (data collection every 5 minutes, monthly sync daily at 5:55 AM)
- **Services**: OpenRC manages `SBFspotUploadDaemon` for continuous uploads
- **Config Generation**: `generateConfig.sh` converts Home Assistant options to `SBFspot.cfg` and `SBFspotUpload.cfg`

### Surveillancestream Add-on (`surveillancestream/`)

Web UI for surveillance streams:
- **Stack**: Next.js frontend (port 3001) + Node.js/TypeScript backend (port 3002) + Nginx reverse proxy
- **API**: GraphQL endpoint at `/graphql`
- **Services**: s6-overlay supervises nginx, backend, and frontend processes
- **Config**: `rootfs/etc/cont-init.d/` scripts generate `.env` files from Home Assistant options
- **Nginx Templates**: `rootfs/etc/nginx/templates/` uses Tempio (`.gtpl`) for dynamic config generation

### Configuration Flow

1. User sets options in Home Assistant UI
2. Container starts and reads options via `bashio` utilities
3. Init scripts generate config files from templates
4. Services start with generated configuration

## Conventions learned the hard way

These are not visible in the code and each one cost real debugging time:

- **Match the base image to the upstream binary's libc.** `ghcr.io/hassio-addons/base` is Alpine/musl. A glibc binary copied from a Debian-based upstream image will not run on it — use `ghcr.io/home-assistant/{arch}-base-debian` instead (`buzz` does; `wealthfolio` can use Alpine because its upstream is Alpine). Check with `ldd` before choosing.
- **Never read a boolean option with `jq '.[$k] // empty'`.** jq treats `false` as falsy, so a boolean set to `false` is indistinguishable from an absent key and silently collapses to the default. Use `has($k)` — see `buzz::opt_bool` in `buzz/rootfs/usr/lib/buzz/common.sh`. This bug shipped twice before it was caught.
- **Test `/data` permissions on a Docker named volume, never a macOS bind mount.** Docker Desktop synthesises ownership for bind-mounted host files, so `0700`/`0600` modes are not enforced and permission bugs stay hidden until the add-on hits real hardware.
- **`finish` scripts use the s6-overlay v3 path** `/run/s6/basedir/bin/halt`. `surveillancestream` still uses the v2 `s6-svscanctl` form; do not copy it. Give a service no `finish` script when its death should not take the add-on down.
- **Legacy `services.d` has no ordering.** Whichever service owns the dependency graph must wait for its peers explicitly (`buzz/rootfs/etc/services.d/buzz-relay/run` does this). Do not copy `surveillancestream`'s `bashio::net.wait_for 28765` — that port belongs to motionEye and nothing in that add-on listens on it.
- **Hand secrets to non-root services through mode-restricted files**, not argv or shell interpolation; generate them hex-only, since these values end up inside `postgres://`, `redis://` and `MC_HOST_*` URIs where base64 padding characters corrupt the URI.

## Key Files

- `repository.json`: Repository metadata for Home Assistant
- `*/config.json`: Add-on configuration schema (drives Home Assistant UI)
- `surveillancestream/rootfs/etc/nginx/includes/upstream.conf`: Backend/frontend port definitions
- `sbfspot/generateConfig.sh`: Maps all 42 configuration options to SBFspot config format
