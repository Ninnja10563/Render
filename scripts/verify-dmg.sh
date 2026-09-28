#!/bin/bash
set -euo pipefail
VERIFY_LOG=$(mktemp)
trap 'rm -f "$VERIFY_LOG"' EXIT
for attempt in 1 2 3; do
    if hdiutil verify "$1" > "$VERIFY_LOG" 2>&1; then
        cat "$VERIFY_LOG"
        exit 0
    else
        verify_status=$?
    fi
    cat "$VERIFY_LOG" >&2
    if ! grep -q 'Resource temporarily unavailable' "$VERIFY_LOG" || [ "$attempt" -eq 3 ]; then
        exit "$verify_status"
    fi
    sleep 2
done
