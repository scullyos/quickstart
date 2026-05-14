#!/bin/sh
# Kibana one-shot setup. Runs once after `kibana` is healthy.
# Creates the cross-service index pattern. Idempotent.
#
# Lifted from gitops/apps/development/log-grabber/fluent-bit-forwarder.yaml.
#
# Required env: ES_USERNAME, ES_PASSWORD.

set -e

KIBANA_BASE="http://kibana:5601"

echo "[kibana-setup] Waiting for Kibana to be ready..."
while ! curl -fs -u "${ES_USERNAME}:${ES_PASSWORD}" "${KIBANA_BASE}/api/status" > /dev/null 2>&1; do
    echo "[kibana-setup] Waiting for Kibana..."
    sleep 10
done

echo "[kibana-setup] Creating cross-service index pattern..."
curl -s -u "${ES_USERNAME}:${ES_PASSWORD}" \
    -X POST "${KIBANA_BASE}/api/saved_objects/index-pattern/microservices-logs" \
    -H "Content-Type: application/json" \
    -H "kbn-xsrf: true" \
    -d '{"attributes":{"title":"*-ms-*","timeFieldName":"@timestamp"}}' \
    || echo "[kibana-setup] Cross-service index pattern already exists (or could not be created — check Kibana logs)."

# Set Discover defaults so opening the Discover tab lands on the microservices
# index pattern with the platform logger's JSON fields pre-selected as columns.
# `time` is the timeFieldName (@timestamp) and is rendered automatically on the
# left of every row — it is not part of `defaultColumns`. The remaining fields
# match the JSON keys emitted by simple-core's logger.util.ts.
# Both endpoints are PUT-style upserts and safe to re-run.
echo "[kibana-setup] Setting default index pattern + Discover columns..."
curl -s -u "${ES_USERNAME}:${ES_PASSWORD}" \
    -X POST "${KIBANA_BASE}/api/kibana/settings" \
    -H "Content-Type: application/json" \
    -H "kbn-xsrf: true" \
    -d '{"changes":{"defaultIndex":"microservices-logs","defaultColumns":["severity","message","errorStack","msreqid","ms","entityType","entityId"]}}' \
    || echo "[kibana-setup] Failed to set Discover defaults — check Kibana logs."

echo "[kibana-setup] Done."
