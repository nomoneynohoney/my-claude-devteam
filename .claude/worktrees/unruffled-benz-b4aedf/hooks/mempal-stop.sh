#!/bin/bash
# MemPalace Stop hook — mine the just-ended session into the palace
# so future sessions can search what we learned.
#
# Safe no-op when mempalace is not on $PATH. We re-emit stdin so other
# Stop hooks downstream see the same payload we received.

INPUT=$(cat)

if command -v mempalace >/dev/null 2>&1; then
  # Try the CLI hook runner; fall back to the python module invocation
  # that older mempalace versions use; silently swallow any error so
  # a broken palace never blocks Claude Code from finishing the session.
  echo "$INPUT" | mempalace hook run --hook stop --harness claude-code 2>/dev/null \
    || echo "$INPUT" | python3 -m mempalace hook run --hook stop --harness claude-code 2>/dev/null \
    || true
fi

printf '%s' "$INPUT"
exit 0
