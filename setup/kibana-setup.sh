#!/bin/sh
# Kibana healthcheck + one-time setup. Runs inside the kibana container.
# Healthy only when Kibana answers AND the setup below has been applied once,
# so `docker compose up --wait` needs no separate one-shot container.
#
# The setup creates the cross-service index pattern and the Discover defaults.
# Both calls are idempotent; a marker in /tmp skips them on later checks (a
# recreated container starts without the marker and re-applies them).
#
# Uses the container's own ELASTICSEARCH_USERNAME / ELASTICSEARCH_PASSWORD.

KIBANA_BASE="http://localhost:5601"
AUTH="${ELASTICSEARCH_USERNAME}:${ELASTICSEARCH_PASSWORD}"
MARKER="/tmp/.kibana-setup-done"

curl -sf -u "$AUTH" "${KIBANA_BASE}/api/status" > /dev/null || exit 1
[ -f "$MARKER" ] && exit 0

# 200 = created, 409 = already exists; both mean the pattern is in place.
code=$(curl -s -o /dev/null -w '%{http_code}' -u "$AUTH" \
    -X POST "${KIBANA_BASE}/api/saved_objects/index-pattern/microservices-logs" \
    -H "Content-Type: application/json" \
    -H "kbn-xsrf: true" \
    -d '{"attributes":{"title":"*-ms-*","timeFieldName":"@timestamp"}}')
case "$code" in
    200|409) ;;
    *) echo "index pattern setup returned HTTP $code"; exit 1 ;;
esac

# Discover lands on the microservices index pattern with the platform logger's
# JSON fields as columns (they match simple-core's logger.util.ts keys).
curl -sf -o /dev/null -u "$AUTH" \
    -X POST "${KIBANA_BASE}/api/kibana/settings" \
    -H "Content-Type: application/json" \
    -H "kbn-xsrf: true" \
    -d '{"changes":{"defaultIndex":"microservices-logs","defaultColumns":["severity","message","errorStack","msreqid","ms","entityType","entityId"]}}' \
    || { echo "Discover defaults setup failed"; exit 1; }

touch "$MARKER"
