#!/bin/sh
# Elasticsearch one-shot setup. Runs once at stack-up after `elasticsearch`
# is healthy. Idempotent — safe to re-run after `docker compose down`, and
# also safe if the container itself is restarted by a subsequent `up -d`
# (which `compose up` does for any exited service, regardless of
# `restart: "no"`). The previous version relied on the built-in `elastic`
# user for its wait loop, but `elastic` gets disabled at the end of a
# successful run — so a second run on the same data volume would loop
# forever. We now prefer ${ES_USERNAME}, which we provision and keep
# enabled, and only fall back to `elastic` on a genuine first boot.
#
# Lifted from gitops/apps/development/log-grabber/fluent-bit-forwarder.yaml
# (the k8s init container). The hostname `elasticsearch` resolves the same
# way in compose as it does via k8s service DNS.
#
# Required env: ES_USERNAME, ES_PASSWORD.

set -e

ES_BASE="http://elasticsearch:9200"

# Wait for ES to be reachable AND for one of our credentials to authenticate.
# On first boot, only `elastic` works (built-in superuser, password set via
# ELASTIC_PASSWORD). After we provision ${ES_USERNAME} and disable `elastic`,
# only ${ES_USERNAME} works. Try the provisioned user first so re-runs of
# this script (after `elastic` was disabled by a previous run) succeed.
echo "[es-setup] Waiting for Elasticsearch..."
while true; do
    if curl -fs -u "${ES_USERNAME}:${ES_PASSWORD}" "${ES_BASE}/_cluster/health" > /dev/null 2>&1; then
        AUTH="${ES_USERNAME}:${ES_PASSWORD}"
        BOOTSTRAPPED=1
        break
    fi
    if curl -fs -u "elastic:${ES_PASSWORD}" "${ES_BASE}/_cluster/health" > /dev/null 2>&1; then
        AUTH="elastic:${ES_PASSWORD}"
        BOOTSTRAPPED=0
        break
    fi
    sleep 5
done

if [ "$BOOTSTRAPPED" = "1" ]; then
    echo "[es-setup] Authenticated as ${ES_USERNAME} — already bootstrapped, reconciling roles/templates."
else
    echo "[es-setup] Authenticated as elastic — first-time bootstrap."
fi

# The first security-API call forces creation of the .security-7 index,
# which on a cold host can exceed the 30s cluster-event timeout and return
# 503. curl -s swallows that, so retry until ES acks a 200 and fail fast if
# it never does — anonymous fluent-bit writes 401 without this role.
echo "[es-setup] Ensuring fluent_writer role..."
i=0
until [ "$(curl -s -o /dev/null -w '%{http_code}' -u "$AUTH" \
    -X PUT "${ES_BASE}/_security/role/fluent_writer" \
    -H "Content-Type: application/json" \
    -d '{"indices":[{"names":["dev-ms-logs-*","*-ms-*"],"privileges":["create_index","index","write","create"]}]}')" = "200" ]; do
    i=$((i + 1))
    if [ "$i" -ge 12 ]; then
        echo "[es-setup] FATAL: fluent_writer role not created after $i attempts" >&2
        exit 1
    fi
    echo "[es-setup] role PUT not ready (attempt $i), retrying in 10s..."
    sleep 10
done
echo

echo "[es-setup] Ensuring microservices index template..."
curl -s -u "$AUTH" \
    -X PUT "${ES_BASE}/_index_template/microservices-template" \
    -H "Content-Type: application/json" \
    -d '{"index_patterns":["*-ms-*"],"template":{"mappings":{"properties":{"@timestamp":{"type":"date","format":"strict_date_optional_time||yyyy-MM-dd'\''T'\''HH:mm:ss.SSS||yyyy-MM-dd'\''T'\''HH:mm:ss.SSSZZ"},"ms":{"type":"keyword"},"message":{"type":"text"},"traceId":{"type":"keyword"},"spanId":{"type":"keyword"},"msreqid":{"type":"keyword"},"entityType":{"type":"keyword"},"entityId":{"type":"keyword"},"errorStack":{"type":"text"},"context":{"type":"keyword"},"level":{"type":"keyword"}}}}}'
echo

if [ "$BOOTSTRAPPED" = "0" ]; then
    echo "[es-setup] Creating superuser ${ES_USERNAME}..."
    curl -s -u "$AUTH" \
        -X POST "${ES_BASE}/_security/user/${ES_USERNAME}" \
        -H "Content-Type: application/json" \
        -d "{\"password\":\"${ES_PASSWORD}\",\"roles\":[\"superuser\"]}"
    echo

    echo "[es-setup] Disabling the elastic built-in user..."
    curl -s -u "${ES_USERNAME}:${ES_PASSWORD}" \
        -X PUT "${ES_BASE}/_security/user/elastic/_disable"
    echo
fi

echo "[es-setup] Done."
