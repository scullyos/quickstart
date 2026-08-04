#!/bin/sh
#
# Reports which quickstart checkout owns the running environment.
#
# Usage:
#   ./scripts/sh/whoami.sh        # this checkout's identity + who owns it
#   ./scripts/sh/whoami.sh --all  # every ScullyOS stack running on this host
#
# Answers the question you actually have when several quickstarts are
# checked out: "the stack on :18080 — which directory started it?".
# Reads docker compose's own project labels, so it works even for stacks
# brought up before this script existed.
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
QUICKSTART_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
BASE_ENV_FILE="${QUICKSTART_BASE_ENV_FILE:-$QUICKSTART_DIR/.env.base}"
ENV_FILE="${QUICKSTART_ENV_FILE:-$QUICKSTART_DIR/.env}"

cd "$QUICKSTART_DIR" || exit 1

. "$SCRIPT_DIR/stack-identity.sh"

# Every compose project with at least one container on this host, as
# "<project>\t<working_dir>". Derived from labels rather than
# `docker compose ls` so stopped-but-present stacks show up too.
list_all_stacks() {
    docker ps -a \
        --format '{{.Label "com.docker.compose.project"}}\t{{.Label "com.docker.compose.project.working_dir"}}\t{{.State}}' \
        2>/dev/null \
        | awk -F'\t' '$1 != "" { key = $1 "\t" $2; if (!(key in seen)) { seen[key]; print $1 "\t" $2 "\t" $3 } }'
}

if [ "${1:-}" = "--all" ]; then
    printf '%-20s %-10s %s\n' 'STACK' 'STATE' 'STARTED FROM'
    list_all_stacks | while IFS="$(printf '\t')" read -r project dir state; do
        printf '%-20s %-10s %s\n' "$project" "$state" "${dir:-<unknown>}"
    done
    exit 0
fi

echo "─── This checkout ───"
echo "  directory:  $QUICKSTART_DIR"
echo "  stack:      $STACK_NAME"
echo "  containers: ${STACK_PREFIX}<service>"

owner=$(stack_running_dir)

echo
echo "─── Running stack '$STACK_NAME' ───"
if [ -z "$owner" ]; then
    echo "  not running"
    exit 0
fi

echo "  started from: $owner"
if [ "$(normalize_path "$owner")" = "$(normalize_path "$STACK_PROJECT_DIR")" ]; then
    echo "  owner:        this checkout"
    exit 0
fi

echo "  owner:        ANOTHER checkout"
echo
echo "⚠ './scripts/sh/up.sh' from here would recreate that stack's containers"
echo "  against its volumes. Stop it there first, or give this checkout its own"
echo "  identity — see scripts/sh/stack-identity.sh."
exit 1
