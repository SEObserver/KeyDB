#!/bin/sh
set -eu

case "${1:-}" in
    -*|*.conf)
        set -- keydb-server "$@"
        ;;
esac

if [ "${1:-}" = keydb-server ] && [ "$(id -u)" = 0 ]; then
    find /data ! -user keydb -exec chown keydb:keydb '{}' +
    exec gosu keydb "$0" "$@"
fi

exec "$@"
