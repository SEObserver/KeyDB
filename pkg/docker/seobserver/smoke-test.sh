#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <image> <40-character revision> <version>" >&2
    exit 2
fi

readonly image=$1
readonly revision=$2
readonly version=$3
readonly short_revision=${revision:0:8}
readonly prefix="keydb-seobserver-smoke-$$"
readonly basic_container="$prefix-basic"
readonly tls_container="$prefix-tls"
readonly node_a="$prefix-a"
readonly node_b="$prefix-b"
readonly data_volume="$prefix-data"
readonly network="$prefix-net"

cleanup() {
    local status=$?
    if [[ $status -ne 0 ]]; then
        for container in "$basic_container" "$tls_container" "$node_a" "$node_b"; do
            docker logs "$container" 2>/dev/null || true
        done
    fi
    docker rm --force "$basic_container" "$tls_container" "$node_a" "$node_b" >/dev/null 2>&1 || true
    docker volume rm "$data_volume" >/dev/null 2>&1 || true
    docker network rm "$network" >/dev/null 2>&1 || true
    exit "$status"
}
trap cleanup EXIT INT TERM

wait_for_ping() {
    local container=$1
    local tls=${2:-no}
    local attempt
    for attempt in {1..60}; do
        if [[ $tls == yes ]]; then
            if docker exec "$container" keydb-cli \
                --tls \
                --cacert /tls/ca.crt \
                --cert /tls/client.crt \
                --key /tls/client.key \
                ping 2>/dev/null | tr -d '\r' | grep -qx PONG; then
                return 0
            fi
        elif docker exec "$container" keydb-cli ping 2>/dev/null | tr -d '\r' | grep -qx PONG; then
            return 0
        fi
        sleep 1
    done
    echo "KeyDB did not become ready in $container" >&2
    return 1
}

wait_for_value() {
    local container=$1
    local key=$2
    local expected=$3
    local attempt value
    for attempt in {1..60}; do
        value=$(docker exec "$container" keydb-cli --raw get "$key" 2>/dev/null | tr -d '\r' || true)
        if [[ $value == "$expected" ]]; then
            return 0
        fi
        sleep 1
    done
    echo "$key did not replicate to $container" >&2
    return 1
}

[[ $revision =~ ^[0-9a-f]{40}$ ]]
[[ $(docker image inspect --format '{{.Architecture}}' "$image") == amd64 ]]
[[ $(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.revision"}}' "$image") == "$revision" ]]
[[ $(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.version"}}' "$image") == "$version" ]]
docker run --rm --entrypoint keydb-server "$image" --version | grep -F "sha=$short_revision:0"

docker volume create "$data_volume" >/dev/null
docker run --detach --name "$basic_container" --volume "$data_volume:/data" "$image" >/dev/null
wait_for_ping "$basic_container"
[[ $(docker exec "$basic_container" awk '/^Uid:/ {print $2}' /proc/1/status) == 999 ]]
[[ $(docker exec "$basic_container" keydb-cli set persisted release-smoke | tr -d '\r') == OK ]]
[[ $(docker exec "$basic_container" keydb-cli set expiring value PX 60000 | tr -d '\r') == OK ]]
ttl=$(docker exec "$basic_container" keydb-cli pttl expiring | tr -d '\r')
((ttl > 0 && ttl <= 60000))
docker exec "$basic_container" keydb-cli bgsave >/dev/null
for attempt in {1..60}; do
    if docker exec "$basic_container" test -s /data/dump.rdb; then
        break
    fi
    sleep 1
done
docker exec "$basic_container" test -s /data/dump.rdb
docker stop --time 30 "$basic_container" >/dev/null
docker rm "$basic_container" >/dev/null
docker run --detach --name "$basic_container" --volume "$data_volume:/data" "$image" >/dev/null
wait_for_ping "$basic_container"
[[ $(docker exec "$basic_container" keydb-cli --raw get persisted | tr -d '\r') == release-smoke ]]

if [[ ! -f tests/tls/server.crt ]]; then
    ./utils/gen-test-certs.sh
fi
chmod 0644 tests/tls/server.key tests/tls/client.key
docker run --detach --name "$tls_container" \
    --volume "$PWD/tests/tls:/tls:ro" \
    "$image" \
    keydb-server \
    --port 0 \
    --tls-port 6379 \
    --tls-cert-file /tls/server.crt \
    --tls-key-file /tls/server.key \
    --tls-ca-cert-file /tls/ca.crt \
    --protected-mode no \
    --save '' >/dev/null
wait_for_ping "$tls_container" yes

docker network create "$network" >/dev/null
for node in "$node_a" "$node_b"; do
    docker run --detach --name "$node" --network "$network" "$image" \
        keydb-server \
        --active-replica yes \
        --multi-master yes \
        --protected-mode no \
        --save '' >/dev/null
    wait_for_ping "$node"
done
docker exec "$node_a" keydb-cli replicaof "$node_b" 6379 >/dev/null
docker exec "$node_b" keydb-cli replicaof "$node_a" 6379 >/dev/null
[[ $(docker exec "$node_a" keydb-cli set from-a A | tr -d '\r') == OK ]]
wait_for_value "$node_b" from-a A
[[ $(docker exec "$node_b" keydb-cli set from-b B | tr -d '\r') == OK ]]
wait_for_value "$node_a" from-b B
[[ $(docker exec "$node_a" keydb-cli set volatile value PX 1500 | tr -d '\r') == OK ]]
wait_for_value "$node_b" volatile value
sleep 3
[[ $(docker exec "$node_a" keydb-cli exists volatile | tr -d '\r') == 0 ]]
[[ $(docker exec "$node_b" keydb-cli exists volatile | tr -d '\r') == 0 ]]

echo "Container smoke tests passed for $image ($revision)."
