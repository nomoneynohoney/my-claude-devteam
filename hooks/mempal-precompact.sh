#!/bin/bash
# MemPalace PreCompact hook — snapshot important session context into
# the palace right before Claude Code compresses it. Stops bug traces,
# vuln PoCs, and design decisions from being lost to the context squash.
#
# Safe no-op when neither mempal-safe nor mempalace is on $PATH. Re-emits
# stdin unchanged. mempal-safe is a local wrapper that quarantines stale
# ChromaDB HNSW segments before each call.

INPUT=$(cat)

if command -v mempal-safe >/dev/null 2>&1 || command -v mempalace >/dev/null 2>&1; then
  echo "$INPUT" | mempal-safe hook run --hook precompact --harness claude-code 2>/dev/null \
    || echo "$INPUT" | python3 -m mempalace hook run --hook precompact --harness claude-code 2>/dev/null \
    || true
fi

printf '%s' "$INPUT"
exit 0
