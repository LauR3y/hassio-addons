#!/usr/bin/with-contenv bashio
# ==============================================================================
# Home Assistant Add-on: Buzz
# Initialises the PostgreSQL 17 cluster in /data/postgres on first boot and
# creates the buzz database. Idempotent: later boots only verify the tuning
# include is present.
# ==============================================================================
set -e

# shellcheck source=/dev/null
source /usr/lib/buzz/common.sh

PGDATA=/data/postgres
PGBIN=/usr/lib/postgresql/17/bin

install -d -o postgres -g postgres -m 0755 /run/postgresql
# initdb refuses to run in a directory with looser permissions than 0700.
install -d -o postgres -g postgres -m 0700 "${PGDATA}"

if [ ! -s "${PGDATA}/PG_VERSION" ]; then
    bashio::log.info "First boot: initialising the PostgreSQL 17 cluster in ${PGDATA}"
    bashio::log.info "This takes a few minutes on an SD card. Do not restart the add-on."

    # --pwfile: initdb reads the password from a file, so it never appears in
    #   argv or in SQL text.
    # -U buzz: the relay's role is the cluster superuser on purpose -- buzz
    #   migration 0001 runs CREATE EXTENSION pgcrypto, which requires superuser.
    # --auth-local=trust is safe: the socket only exists inside this container.
    s6-setuidgid postgres "${PGBIN}/initdb" \
        -D "${PGDATA}" \
        -U buzz \
        --pwfile="${BUZZ_SECRETS_DIR}/postgres_password" \
        --auth-local=trust \
        --auth-host=scram-sha-256 \
        --encoding=UTF8 \
        --locale=C.UTF-8 \
        --data-checksums

    bashio::log.info "Creating the 'buzz' database"
    s6-setuidgid postgres "${PGBIN}/pg_ctl" -D "${PGDATA}" -w -t 120 \
        -o "-c listen_addresses='' -c unix_socket_directories=/run/postgresql" start
    s6-setuidgid postgres "${PGBIN}/createdb" -h /run/postgresql -U buzz -O buzz buzz
    s6-setuidgid postgres "${PGBIN}/pg_ctl" -D "${PGDATA}" -m fast -w -t 120 stop
    bashio::log.info "PostgreSQL cluster initialised"
else
    # Guard against a future base-image bump moving to a newer major version:
    # PostgreSQL will not open a cluster created by a different major release.
    CLUSTER_VERSION="$(cat "${PGDATA}/PG_VERSION")"
    if [ "${CLUSTER_VERSION}" != "17" ]; then
        bashio::exit.nok "/data/postgres was created by PostgreSQL ${CLUSTER_VERSION}, but this \
add-on ships PostgreSQL 17. Automatic pg_upgrade is not implemented. Restore a backup made with \
the matching version, or dump and reload the data manually."
    fi
fi

# Tuning lives in the image so an add-on upgrade can retune, and is pulled in
# with a single include line appended once rather than rewriting PGDATA.
if ! grep -q 'buzz/postgresql.tuning.conf' "${PGDATA}/postgresql.conf"; then
    printf "\ninclude_if_exists = '/etc/buzz/postgresql.tuning.conf'\n" >> "${PGDATA}/postgresql.conf"
    chown postgres:postgres "${PGDATA}/postgresql.conf"
    bashio::log.info "Enabled the Buzz PostgreSQL tuning include"
fi
