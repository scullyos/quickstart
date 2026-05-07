#!/bin/sh
#
# Brings the quickstart up in detached mode and reports how long it took
# to CREATE all containers. Wraps `docker compose up -d` with timed.sh.
#
# Note: `docker compose up -d` returns as soon as containers are created
# and started — NOT when they're all healthy. Healthcheck convergence
# (mysql + ES + the four MS readiness probes + the *-setup one-shots)
# adds another ~30-60 sec on top. If you want "until everything is
# healthy", append `--wait` (compose v2 supports it):
#
#   ./scripts/sh/up.sh --wait
#
# Forwards any args to docker compose up, e.g.:
#   ./scripts/sh/up.sh --force-recreate
#   ./scripts/sh/up.sh person-ms        # bring up a single service
#
# After the compose run completes, prints the seed admin credentials
# (SEED_USER_NAME / SEED_USER_PASSWORD from quickstart/.env) so the
# operator can log straight into the web app, and warns if LLM_API_KEY
# is unset or still the shipped placeholder — in which case the Admin
# Chat agent stays disabled.
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUICKSTART_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BASE_ENV_FILE="${QUICKSTART_BASE_ENV_FILE:-$QUICKSTART_DIR/.env.base}"
ENV_FILE="${QUICKSTART_ENV_FILE:-$QUICKSTART_DIR/.env}"

# Sentinel that bo-orc treats as "no key configured" — must stay in sync
# with PLACEHOLDER_LLM_API_KEY in bo-orc/src/modules/features/features.controller.ts.
PLACEHOLDER_LLM_API_KEY='replace-with-your-key-or-leave-as-is-to-disable-agent'

cd "$QUICKSTART_DIR" || exit 1

# .env.base ships with the repo and pins the image versions / registry —
# git pull updates it. .env is the user's local file (copied from
# .env.example on first install). Stacking them with --env-file lets a
# pull deliver new versions without the user re-editing .env. Order is
# base first, .env second: same-named vars in .env override .env.base,
# so a user can still pin a specific version locally for a rollback by
# adding it to .env. Existing installs with stale VERSION_* / REGISTRY /
# *_IMAGE lines in their .env should remove them — see README "Upgrading
# from earlier checkouts".
if [ ! -f "$BASE_ENV_FILE" ]; then
    echo "ERROR: $BASE_ENV_FILE is missing. Run 'git pull' to fetch it." >&2
    exit 1
fi
if [ ! -f "$ENV_FILE" ]; then
    echo "ERROR: $ENV_FILE is missing. Copy .env.example to .env and edit before first up." >&2
    exit 1
fi

"$SCRIPT_DIR/timed.sh" "compose up -d" \
    docker compose --env-file "$BASE_ENV_FILE" --env-file "$ENV_FILE" up -d "$@"
exit_code=$?

# Read a `KEY=value` line from $ENV_FILE, stripping optional surrounding
# single or double quotes. Returns empty string if the file or key is
# missing — callers handle the unset case explicitly.
read_env_var() {
    var="$1"
    [ -f "$ENV_FILE" ] || return 0
    line=$(grep -E "^[[:space:]]*${var}=" "$ENV_FILE" | tail -n 1)
    [ -z "$line" ] && return 0
    value="${line#*=}"
    case "$value" in
        \"*\") value="${value#\"}"; value="${value%\"}" ;;
        \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    printf '%s' "$value"
}

seed_user=$(read_env_var SEED_USER_NAME)
seed_pwd=$(read_env_var SEED_USER_PASSWORD)
llm_key=$(read_env_var LLM_API_KEY)

echo
echo "─── Web app login (from $ENV_FILE) ───"
echo "  user:     ${seed_user:-<unset>}"
echo "  password: ${seed_pwd:-<unset>}"

if [ -z "$llm_key" ] || [ "$llm_key" = "$PLACEHOLDER_LLM_API_KEY" ]; then
    echo
    echo "⚠ LLM_API_KEY is not set in $ENV_FILE — the Backoffice AI Agent will not be usable."
    echo "  Replace LLM_API_KEY with a real provider key and restart bo-orc-ms to enable it."
fi

exit "$exit_code"
