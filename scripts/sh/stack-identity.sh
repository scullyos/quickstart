#!/bin/sh
#
# Stack identity — sourced by up.sh / down.sh / pull.sh / whoami.sh.
#
# Answers "which quickstart checkout does this environment belong to?".
# Every checkout used to declare `name: scullyos` with bare container
# names, so several quickstarts shared one compose project, one network
# and one set of volumes: a second `up` silently adopted the first
# stack's containers and its MySQL/ES data. This file gives each
# checkout its own identity so they can coexist, and so the identity is
# visible from the containers, the logs and the web app.
#
# Resolution order for STACK_NAME (first hit wins):
#   1. STACK_NAME already exported in the shell
#   2. STACK_NAME= in .env (then .env.base)
#   3. first non-comment line of .stack-name
#   4. normalised directory basename ("quickstart" -> "scullyos",
#      "quickstart-navis" -> "navis")
#
# Exports STACK_NAME, STACK_PREFIX and the offset-adjusted HOST_PORT_*.
# Shell environment beats --env-file in docker compose's precedence, so
# exporting here is what makes the values reach the compose file.
#
# Callers must set SCRIPT_DIR and QUICKSTART_DIR before sourcing.

# The compose project name a checkout gets when nothing overrides it.
# Keeping the stock quickstart on "scullyos" means existing installs see
# no rename: same project, same containers, same volumes.
STACK_NAME_DEFAULT='scullyos'

STACK_NAME_FILE="${STACK_NAME_FILE:-$QUICKSTART_DIR/.stack-name}"

# The env-file chain to read config from, in docker compose --env-file
# order (later wins). Overlay checkouts (able, blaise) stack four files
# and set this before sourcing; a plain checkout gets the usual two.
STACK_ENV_FILES="${STACK_ENV_FILES:-$BASE_ENV_FILE $ENV_FILE}"

# Read a `KEY=value` line from a stacked env-file list (later files win,
# matching the docker compose --env-file order), stripping optional
# surrounding quotes. Empty string when no file has the key — callers
# handle the unset case explicitly.
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

# Lower-case, strip anything a compose project name can't contain, and
# collapse the leading "quickstart" / "quickstart-" so a checkout named
# quickstart-navis identifies as "navis".
normalize_stack_name() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -e 's/^quickstart-//' -e 's/^quickstart$//' \
              -e 's/[^a-z0-9_-]/-/g' -e 's/^-*//' -e 's/-*$//'
}

# Docker reports working_dir in the host's native form (C:\path on
# Windows) while the shell sees /c/path — fold both to one shape so the
# ownership guard doesn't false-positive on Git Bash / WSL.
normalize_path() {
    printf '%s' "$1" \
        | tr '[:upper:]' '[:lower:]' \
        | sed -e 's#\\#/#g' -e 's#^\([a-z]\):/#/\1/#' -e 's#/*$##'
}

resolve_stack_name() {
    if [ -n "${STACK_NAME:-}" ]; then
        printf '%s' "$STACK_NAME"
        return
    fi

    from_env=$(read_env_var STACK_NAME $STACK_ENV_FILES)
    if [ -n "$from_env" ]; then
        printf '%s' "$from_env"
        return
    fi

    if [ -f "$STACK_NAME_FILE" ]; then
        from_file=$(grep -vE '^[[:space:]]*(#|$)' "$STACK_NAME_FILE" | head -n 1 | tr -d '[:space:]')
        if [ -n "$from_file" ]; then
            printf '%s' "$from_file"
            return
        fi
    fi

    derived=$(normalize_stack_name "$(basename "$QUICKSTART_DIR")")
    printf '%s' "${derived:-$STACK_NAME_DEFAULT}"
}

# Persist the derived name so a later directory rename doesn't silently
# re-identify a stack that already owns containers and volumes.
persist_stack_name() {
    [ -f "$STACK_NAME_FILE" ] && return 0
    [ -n "$(read_env_var STACK_NAME $STACK_ENV_FILES)" ] && return 0
    {
        echo "# Stack identity for this quickstart checkout — see scripts/sh/stack-identity.sh."
        echo "# Written on first 'up'. Change it only while the stack is down:"
        echo "# the compose project name derives from it, and renaming a running"
        echo "# stack orphans its containers and volumes."
        echo "$STACK_NAME"
    } > "$STACK_NAME_FILE"
}

# Container names stay bare for the default stack (person-ms, mysql, …)
# so existing installs, docs and the fluent-bit regex keep working; a
# named stack prefixes them (navis-person-ms).
resolve_stack_prefix() {
    if [ "$STACK_NAME" = "$STACK_NAME_DEFAULT" ]; then
        printf ''
    else
        printf '%s-' "$STACK_NAME"
    fi
}

# Shift every published host port by PORT_OFFSET so a second stack comes
# up without hand-editing .env. Offset 0 (the default) re-exports the
# configured values unchanged.
apply_port_offset() {
    # Ports are rewritten in place, so a second call would shift them
    # again. Callers that source this file more than once get a no-op.
    [ -n "${STACK_PORTS_APPLIED:-}" ] && return 0

    offset=$(read_env_var PORT_OFFSET $STACK_ENV_FILES)
    offset="${PORT_OFFSET:-$offset}"
    offset="${offset:-0}"

    case "$offset" in
        ''|*[!0-9]*)
            echo "ERROR: PORT_OFFSET must be a non-negative integer (got '$offset')." >&2
            return 1
            ;;
    esac

    PORT_OFFSET="$offset"
    export PORT_OFFSET

    for port_var in HOST_PORT_FRONTEND HOST_PORT_BO_ORC HOST_PORT_KIBANA; do
        eval "current=\${$port_var:-}"
        [ -z "$current" ] && current=$(read_env_var "$port_var" $STACK_ENV_FILES)
        [ -z "$current" ] && continue
        case "$current" in
            ''|*[!0-9]*)
                echo "ERROR: $port_var must be a port number (got '$current')." >&2
                return 1
                ;;
        esac
        eval "export $port_var=\$((current + offset))"
    done

    STACK_PORTS_APPLIED=1
    export STACK_PORTS_APPLIED
}

# The directory that started the containers currently claiming this
# compose project name. Empty when the project isn't running.
stack_running_dir() {
    cid=$(docker ps -aq --filter "label=com.docker.compose.project=$STACK_NAME" 2>/dev/null | head -n 1)
    [ -z "$cid" ] && return 0
    docker inspect "$cid" \
        --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' 2>/dev/null
}

# Fail fast when another checkout already owns this project name.
# Without this, compose happily recreates the other stack's containers
# against its volumes — the data-contamination case this whole file
# exists to prevent.
assert_stack_ownership() {
    owner=$(stack_running_dir)
    [ -z "$owner" ] && return 0
    [ "$(normalize_path "$owner")" = "$(normalize_path "$QUICKSTART_DIR")" ] && return 0

    cat >&2 <<EOF
ERROR: compose project '$STACK_NAME' is already in use by another quickstart.

  running stack started from: $owner
  this checkout:              $QUICKSTART_DIR

Continuing would recreate that stack's containers against its volumes
(${STACK_NAME}_mysql-data, ${STACK_NAME}_es-data) and mix the two
environments' data. Pick one:

  1. Stop the other stack:      cd "$owner" && ./scripts/sh/down.sh
  2. Give this checkout its own identity, then bring it up:
       echo "<name>" > "$STACK_NAME_FILE"
       # ports must not clash with the running stack — either set
       # PORT_OFFSET=100 in .env, or set HOST_PORT_* explicitly
EOF
    return 1
}

# A hand-set include regex that predates this stack's prefix matches no
# container at all, so log shipping stops with nothing in the output to
# say why. This shipped as a warning first and a real install sailed past
# it — a config value that cannot match anything is a structural error, so
# it blocks the up instead.
assert_fluent_bit_regex_matches_stack() {
    [ -z "$STACK_PREFIX" ] && return 0
    regex=$(read_env_var FLUENT_BIT_CONTAINER_INCLUDE_REGEX $STACK_ENV_FILES)
    [ -z "$regex" ] && return 0
    case "$regex" in
        *"$STACK_PREFIX"*) return 0 ;;
    esac

    cat >&2 <<EOF
ERROR: FLUENT_BIT_CONTAINER_INCLUDE_REGEX cannot match this stack's containers.

  configured:       $regex
  container prefix: $STACK_PREFIX

This stack's containers are named ${STACK_PREFIX}<service>, so that regex
matches nothing and no logs would reach Elasticsearch. Fix it in $ENV_FILE:

  1. Preferred — empty the line so the prefix-aware compose default applies:
       FLUENT_BIT_CONTAINER_INCLUDE_REGEX=
  2. Or keep a custom allowlist and include the prefix yourself:
       FLUENT_BIT_CONTAINER_INCLUDE_REGEX=^${STACK_PREFIX}(person|authorization|bo-orc)-ms\$
EOF
    return 1
}

# Overlay checkouts stack their compose file on top of a pinned upstream
# copy. If that copy predates stack identity its container names are
# still hardcoded, and taking a distinct project name would collide with
# whatever else already owns those names. Stay on the legacy identity
# until the pin is bumped — then this lights up on its own.
upstream_supports_stack_identity() {
    [ -z "${STACK_UPSTREAM_COMPOSE:-}" ] && return 0
    grep -q 'STACK_PREFIX' "$STACK_UPSTREAM_COMPOSE" 2>/dev/null
}

STACK_NAME=$(resolve_stack_name)

if ! upstream_supports_stack_identity; then
    if [ "$STACK_NAME" != "$STACK_NAME_DEFAULT" ]; then
        echo "note: upstream pin predates stack identity — staying on '$STACK_NAME_DEFAULT'." >&2
        echo "      Bump .quickstart-version and re-run init.sh to adopt '$STACK_NAME'." >&2
    fi
    STACK_NAME="$STACK_NAME_DEFAULT"
fi

STACK_PREFIX=$(resolve_stack_prefix)
export STACK_NAME STACK_PREFIX
