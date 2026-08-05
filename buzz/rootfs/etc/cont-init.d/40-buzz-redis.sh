#!/usr/bin/with-contenv bashio
# ==============================================================================
# Home Assistant Add-on: Buzz
# Renders the Redis configuration. The password is written into a 0640 file that
# only root and the redis user can read, so it never reaches a command line.
# ==============================================================================
set -e

# shellcheck source=/dev/null
source /usr/lib/buzz/common.sh

REDIS_CONF="${BUZZ_RUN_DIR}/redis.conf"

# Persistence is deliberately off. Postgres is canonical for members, channels
# and messages; Redis here is pub/sub plus connection pooling, and buzz-pubsub
# reconnects with backoff. Disabling RDB and AOF removes a continuous source of
# flash wear and speeds up boot.
cat > "${REDIS_CONF}" <<'EOF'
bind 127.0.0.1
port 6379
protected-mode yes
dir /data/redis
save ""
appendonly no
maxmemory 128mb
maxmemory-policy noeviction
daemonize no
supervised no
loglevel notice
EOF

printf 'requirepass %s\n' "$(cat "${BUZZ_SECRETS_DIR}/redis_password")" >> "${REDIS_CONF}"

chown root:redis "${REDIS_CONF}"
chmod 640 "${REDIS_CONF}"
