#!/bin/sh
#
# Tears the quickstart down and reports how long it took. Wraps
# `docker compose down` with timed.sh. By default, named volumes
# (mysql + ES data) are PRESERVED so a subsequent `up` keeps your data.
#
# Usage:
#   ./scripts/sh/down.sh             # stop containers, KEEP volumes
#   ./scripts/sh/down.sh --wipe      # stop containers AND wipe volumes
#                                    # (fresh start; admin re-seeded on next up)
#
# `-v` is also accepted as an alias for `--wipe` to mirror the docker
# compose flag.
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUICKSTART_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BASE_ENV_FILE="${QUICKSTART_BASE_ENV_FILE:-$QUICKSTART_DIR/.env.base}"
ENV_FILE="${QUICKSTART_ENV_FILE:-$QUICKSTART_DIR/.env}"

cd "$QUICKSTART_DIR" || exit 1

# See up.sh for why both env files are stacked. Down doesn't strictly
# need image-version interpolation (containers are matched by name), but
# compose still parses the YAML and warns on unset vars — passing both
# files keeps output clean and behaviour consistent with up / pull.
if [ ! -f "$BASE_ENV_FILE" ]; then
    echo "ERROR: $BASE_ENV_FILE is missing. Run 'git pull' to fetch it." >&2
    exit 1
fi
if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: $ENV_FILE is missing. Copy .env.example to .env first." >&2
    exit 1
fi

COMPOSE="docker compose --env-file $BASE_ENV_FILE --env-file $ENV_FILE"

case "${1:-}" in
    -v|--wipe|--volumes)
        exec "$SCRIPT_DIR/timed.sh" "compose down -v (volumes WIPED)" \
            $COMPOSE down -v
        ;;
    ""|--keep)
        exec "$SCRIPT_DIR/timed.sh" "compose down (volumes kept)" \
            $COMPOSE down
        ;;
    -h|--help)
        sed -n '3,16p' "$0"
        exit 0
        ;;
    *)
        echo "Unknown option: $1" >&2
        echo "Usage: $0 [--wipe | --keep]   (default: keep)" >&2
        exit 1
        ;;
esac
