#!/bin/sh
#
# Pulls all images for the quickstart and reports how long it took.
# Wraps `docker compose pull` with timed.sh.
#
# Usage:
#   ./scripts/sh/pull.sh
#
# Forwards any args to docker compose pull, e.g.:
#   ./scripts/sh/pull.sh --quiet
#   ./scripts/sh/pull.sh person-ms       # pull a single service
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUICKSTART_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BASE_ENV_FILE="${QUICKSTART_BASE_ENV_FILE:-$QUICKSTART_DIR/.env.base}"
ENV_FILE="${QUICKSTART_ENV_FILE:-$QUICKSTART_DIR/.env}"

cd "$QUICKSTART_DIR" || exit 1

# See up.sh for why both env files are stacked.
if [ ! -f "$BASE_ENV_FILE" ]; then
    echo "ERROR: $BASE_ENV_FILE is missing. Run 'git pull' to fetch it." >&2
    exit 1
fi
if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: $ENV_FILE is missing. Copy .env.example to .env first." >&2
    exit 1
fi

exec "$SCRIPT_DIR/timed.sh" "compose pull" \
    docker compose --env-file "$BASE_ENV_FILE" --env-file "$ENV_FILE" pull "$@"
