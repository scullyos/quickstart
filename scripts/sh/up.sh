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
# If the compose run succeeded, prints the web-app URL (built from
# HOST_BIND / HOST_PORT_FRONTEND, with the same defaults as
# docker-compose.yml: 127.0.0.1:18080) and the seed admin credentials
# (SEED_USER_NAME / SEED_USER_PASSWORD from quickstart/.env) so the
# operator can log straight in, and warns if LLM_API_KEY is still the
# shipped placeholder — in which case the Admin Chat agent is enabled
# (USE_AGENT=yes) but can't respond until a real key is set. On failure
# (compose exit non-zero) the credentials
# block is suppressed: half-up stacks shouldn't advertise a login that
# doesn't work yet.
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUICKSTART_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BASE_ENV_FILE="${QUICKSTART_BASE_ENV_FILE:-$QUICKSTART_DIR/.env.base}"
ENV_FILE="${QUICKSTART_ENV_FILE:-$QUICKSTART_DIR/.env}"

# The placeholder LLM_API_KEY that .env.example ships — must stay in sync
# with the LLM_API_KEY value in .env.example. Used only to nudge the operator
# to set a real key; it lets the stack boot but the agent can't respond.
PLACEHOLDER_LLM_API_KEY='replace-with-your-llm-api-key'

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

# Read a `KEY=value` line from a stacked env-file list (later files
# override earlier ones, matching the docker compose --env-file order),
# stripping optional surrounding single or double quotes. Returns empty
# string if no file has the key — callers handle the unset case
# explicitly. Same precedence as docker-compose.yml's ${VAR:-default}
# fallbacks, so the printed URL matches what compose actually published.
read_env_var() {
    var="$1"
    shift
    value=""
    for f in "$@"; do
        [ -f "$f" ] || continue
        line=$(grep -E "^[[:space:]]*${var}=" "$f" | tail -n 1)
        [ -z "$line" ] && continue
        value="${line#*=}"
        case "$value" in
            \"*\") value="${value#\"}"; value="${value%\"}" ;;
            \'*\') value="${value#\'}"; value="${value%\'}" ;;
        esac
    done
    printf '%s' "$value"
}

if [ "$exit_code" -ne 0 ]; then
    # Half-up stack — don't advertise login details for a webapp that
    # may not be reachable. The compose output above already shows what
    # failed; re-run after fixing.
    exit "$exit_code"
fi

seed_user=$(read_env_var SEED_USER_NAME "$BASE_ENV_FILE" "$ENV_FILE")
seed_pwd=$(read_env_var SEED_USER_PASSWORD "$BASE_ENV_FILE" "$ENV_FILE")
llm_key=$(read_env_var LLM_API_KEY "$BASE_ENV_FILE" "$ENV_FILE")
host_bind=$(read_env_var HOST_BIND "$BASE_ENV_FILE" "$ENV_FILE")
host_port=$(read_env_var HOST_PORT_FRONTEND "$BASE_ENV_FILE" "$ENV_FILE")
webapp_url="http://${host_bind:-127.0.0.1}:${host_port:-18080}"

echo
echo "─── Web app login (from $ENV_FILE) ───"
echo "  url:      $webapp_url"
echo "  user:     ${seed_user:-<unset>}"
echo "  password: ${seed_pwd:-<unset>}"

if [ -z "$llm_key" ] || [ "$llm_key" = "$PLACEHOLDER_LLM_API_KEY" ]; then
    echo
    echo "⚠ LLM_API_KEY is still the placeholder in $ENV_FILE — the Backoffice AI Agent"
    echo "  is enabled but can't respond until you set a real key (or set USE_AGENT=no to disable it)."
    echo "  To set a key:"
    echo "    1. Get a provider API key:"
    echo "         Google Gemini (default): https://aistudio.google.com/apikey"
    echo "         Anthropic:               https://console.anthropic.com/settings/keys"
    echo "    2. Edit $ENV_FILE and set:"
    echo "         LLM_API_KEY=<your key>"
    echo "       (Switching providers? Also set LLM_PROVIDER and LLM_MODEL — see the"
    echo "        'Enabling the Admin Chat panel' section of the README.)"
    echo "    3. Recreate bo-orc-ms so it picks up the new env:"
    echo "         ./scripts/sh/up.sh --force-recreate --no-deps bo-orc-ms"
    echo "       (--no-deps stops compose from also recreating mysql / person-ms /"
    echo "        authorization-ms via the depends_on chain.)"
fi

exit "$exit_code"
