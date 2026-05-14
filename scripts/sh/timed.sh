#!/bin/sh
#
# timed.sh — run a command, stream its output live, then report elapsed
# wall-clock time as Xm Ys at the end. Preserves the command's exit code.
#
# This is the utility wrapper used by pull.sh / up.sh / down.sh; you can
# also call it directly to time anything.
#
# Usage:
#   ./timed.sh "<label>" <command> [args...]
#
# Examples:
#   ./timed.sh "compose pull" docker compose pull
#   ./timed.sh "ES warm-up"   curl -sf http://localhost:9200/_cluster/health?wait_for_status=green
#

if [ $# -lt 2 ]; then
    echo "Usage: $0 <label> <command> [args...]" >&2
    echo "" >&2
    echo "Runs <command>, streams its output, and prints elapsed time at the end." >&2
    exit 1
fi

label="$1"
shift

echo "▶ $label — starting..."
echo

start_s=$(date +%s)

"$@"
exit_code=$?

end_s=$(date +%s)
elapsed=$((end_s - start_s))
minutes=$((elapsed / 60))
seconds=$((elapsed % 60))

echo

if [ "$exit_code" -eq 0 ]; then
    status_glyph="✔"
else
    status_glyph="✘"
fi

if [ "$minutes" -gt 0 ]; then
    printf "%s %s — done in %dm %02ds (exit %d)\n" "$status_glyph" "$label" "$minutes" "$seconds" "$exit_code"
else
    printf "%s %s — done in %ds (exit %d)\n" "$status_glyph" "$label" "$seconds" "$exit_code"
fi

exit "$exit_code"
