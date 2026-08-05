#!/usr/bin/with-contenv bashio
# ==============================================================================
# Home Assistant Add-on: Buzz
# Prepares the MinIO data directory and the mc client configuration directory.
# The media bucket itself is created by the relay service script, once MinIO
# reports healthy.
# ==============================================================================
set -e

# shellcheck source=/dev/null
source /usr/lib/buzz/common.sh

install -d -o minio -g minio -m 0750 /data/minio
install -d -m 0700 "${BUZZ_RUN_DIR}/mc"
