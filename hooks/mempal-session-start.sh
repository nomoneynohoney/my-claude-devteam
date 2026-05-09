#!/bin/bash
# MemPalace SessionStart hook — surface palace state + cwd-matching drawers at session boot.
#
# Safe no-op when mempalace is not on $PATH. Output goes to stderr so it
# shows up in the Claude Code transcript as a system notice without
# polluting the tool's stdin/stdout contract.

# Consume stdin (Claude Code sends a JSON payload to every hook).
cat >/dev/null

command -v mempalace >/dev/null 2>&1 || exit 0

REPO=$(basename "$PWD" 2>/dev/null)

{
  echo "[mempalace] palace online — status:"
  mempal-safe status 2>/dev/null | head -8 || echo "  (status unavailable)"

  if [ -n "$REPO" ]; then
    echo ""
    echo "[mempalace] memories matching cwd ($REPO):"
    OUT=$(mempal-safe search "$REPO" --limit 3 2>/dev/null)
    if [ -n "$OUT" ]; then
      echo "$OUT" | head -24
    else
      echo "  (no prior memories — first time working on this repo)"
    fi
  fi
} >&2

exit 0
