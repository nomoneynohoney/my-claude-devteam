#!/bin/bash
# MemPalace Stop hook — mine the just-ended session into the palace
# so future sessions can search what we learned.
#
# Safe no-op when neither mempal-safe nor mempalace is on $PATH. We
# re-emit stdin so other Stop hooks downstream see the same payload.

INPUT=$(cat)

if command -v mempal-safe >/dev/null 2>&1 || command -v mempalace >/dev/null 2>&1; then
  # Prefer mempal-safe (local wrapper that quarantines stale HNSW first);
  # fall back to python module invocation for older mempalace versions;
  # silently swallow any error so a broken palace never blocks Claude
  # Code from finishing the session.
  echo "$INPUT" | mempal-safe hook run --hook stop --harness claude-code 2>/dev/null \
    || echo "$INPUT" | python3 -m mempalace hook run --hook stop --harness claude-code 2>/dev/null \
    || true
fi

printf '%s' "$INPUT"
exit 0
