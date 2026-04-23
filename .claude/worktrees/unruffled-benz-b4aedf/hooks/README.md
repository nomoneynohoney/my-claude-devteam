# Hooks

**English · [繁體中文](./README.zh-TW.md)**

Eighteen automation hooks that run at Claude Code's lifecycle events (`PreToolUse`, `PostToolUse`, `Stop`, `PreCompact`, `SessionStart`). They catch common failure modes before they ship: hardcoded secrets, debugger statements, MCP outages, runaway cost, AI-slop UI, stale `console.log`, and more — and (optionally) integrate with [**MemPalace**](https://github.com/marc-ai/mempalace) to give the team cross-session memory.

Each hook is a self-contained script under 75 lines. No external dependencies beyond Node.js and standard Unix tools (`jq`, `git`, `grep`).

## The Hooks

### 💰 `cost-tracker.js`
**Fires:** `Stop` (after every response)
**What it does:** Reads the token usage from the response payload, multiplies by the per-model rate (Opus / Sonnet / Haiku), and appends a JSONL record to `~/.claude/metrics/costs.jsonl`. Use this to see how much each session actually cost.

**Output format:**
```json
{"ts":"2026-04-10T13:14:22Z","model":"claude-opus-4-6","in":42153,"out":5421,"cost_usd":1.0389}
```

### ✋ `commit-quality.js`
**Fires:** `PreToolUse` on `Bash` (when command matches `git commit`)
**What it does:** Before each commit, runs `git diff --cached` to get staged files, then scans them for:
- `debugger` statements in JS/TS/Python
- Hardcoded secrets matching known patterns: `sk-*`, `ghp_*`, `gho_*`, `AKIA*` (AWS), `AIza*` (Google)

If any are found, the commit is blocked with `exit 2` and the offending file(s) logged to stderr.

**Skips:** `git commit --amend` (intentionally — amendments are often doc fixes).

### 🔧 `mcp-health.js`
**Fires:** `PreToolUse` on `mcp__*` (check), `PostToolUseFailure` on `mcp__*` (track)
**What it does:** Tracks MCP server health with exponential backoff. If a server fails with `ECONNREFUSED`, `ENOTFOUND`, `timed out`, `401`, `403`, `429`, `503`, etc., it marks the server unhealthy and skips calls for `30s → 1min → 2min → ... → 10min` until it retries.

State is persisted to `~/.claude/mcp-health-cache.json`. On a successful call after the retry window, the server is marked healthy again.

**Why this matters:** Without this, Claude will keep hammering a dead MCP server, burning context on error messages. With it, calls are skipped until the server is likely back.

### 🛡 `config-protection.js`
**Fires:** `PreToolUse` on `Write | Edit`
**What it does:** Blocks direct edits to `.eslintrc*`, `eslint.config.*`, `.prettierrc*`, `prettier.config.*`, `biome.json`, `.ruff.toml`, `.stylelintrc*`. Forces Claude to fix the source code instead of weakening the linter.

**Customize:** edit the `protectedFiles` set to add your own config files.

### 🎨 `design-quality.js`
**Fires:** `PostToolUse` on `Write | Edit`
**What it does:** On frontend file edits (`.tsx`, `.jsx`, `.vue`, `.css`, `.scss`, `.svelte`, `.astro`), scans for generic AI-slop signals:
- Default CTAs: "Get Started", "Learn More"
- Uniform card grids (`grid-cols-3` or `grid-cols-4`)
- Stock gradients (`bg-gradient-to-*`)
- Generic fonts (Inter, Roboto)

If found, prints a warning (non-blocking) so Claude knows to commit to a more intentional design.

### 📝 `check-console.js`
**Fires:** `Stop` (after every response)
**What it does:** Runs `git diff HEAD --name-only` to find files modified this session, then scans them for `console.log` in non-test, non-config files. Prints a warning (non-blocking) if any are found.

**Excludes:** `*.test.*`, `*.spec.*`, `*.config.*`, `scripts/`, `__tests__/`

### 📊 `audit-log.js`
**Fires:** `PostToolUse` on `Bash`
**What it does:** Appends every Bash command to `~/.claude/bash-commands.log` with timestamps. **Auto-redacts** common secret patterns: `--token=`, `password=`, GitHub tokens, Google API keys, `sshpass -p 'XXX'`.

**Use case:** post-mortem audit of what Claude actually ran during a session.

### 🎯 `batch-format.js`
**Fires:** `Stop` (after every response)
**What it does:** Reads the list of JS/TS files edited this session (accumulated by `accumulator.js`), then runs in batch:
1. `prettier --write` on all of them (if `./node_modules/.bin/prettier` exists)
2. `npx tsc --noEmit --pretty false` to catch type errors
3. Reports TS errors per-file to stderr

Uses a session-scoped temp file (`claude-edited-<session-hash>.txt`) to track which files were edited.

### 📈 `accumulator.js`
**Fires:** `PostToolUse` on `Write | Edit`
**What it does:** The companion to `batch-format.js`. Every time a JS/TS file is edited, appends the path to the session's temp file. At `Stop`, `batch-format.js` reads the list and runs formatters + typecheck in one batch (faster than running per-file).

### 💡 `suggest-compact.js`
**Fires:** `PreToolUse` on `Write | Edit`
**What it does:** Counts tool calls per session via a temp file. At call #50, prints a reminder to consider `/compact`. Every 25 calls after that (#75, #100, #125, ...) prints another reminder.

**Why:** Long sessions burn context. A nudge at the right moment keeps responses fast.

### 🚨 `log-error.sh`
**Fires:** `PostToolUse` on `.*` (every tool)
**What it does:** If any tool output contains error keywords (`error`, `failed`, `ENOENT`, `EACCES`, `permission denied`, `fatal`, `exception`, `traceback`), appends a structured entry to `~/.claude/error-log.md`:
```markdown
## 2026-04-10 13:42:11 - Bash
**Input:** ...
**Error:** ...
**Solution:** (fill in after fix)
```

Use this as your personal error journal — fill in solutions after you fix each one, and search it when you hit a similar error later.

### 🧪 `test-runner.js`
**Fires:** `PostToolUse` on `Write | Edit`
**What it does:** Whenever a JS/TS source file is edited, looks for a sibling test file (`foo.test.ts`, `foo.spec.ts`, `__tests__/foo.test.ts`) and runs it via vitest or jest (whichever is in `node_modules/.bin`). Failures are printed to stderr but do not block. Skips if no test runner is installed.

### 🔒 `branch-protection.js`
**Fires:** `PreToolUse` on `Bash`
**What it does:** Detects git operations on protected branches (`main`, `master`, `production`, `release`, `prod`).

- **Hard block**: force push to a protected branch
- **Hard block**: `git commit` while currently on a protected branch
- **Warn**: any merge / rebase / reset / cherry-pick / revert / checkout on a protected branch

Forces feature-branch workflow without ever silently allowing a direct commit to main.

### 📏 `large-file-warner.js`
**Fires:** `PreToolUse` on `Read`
**What it does:** Checks file size before reading.

- **Warn at 500 KB**: suggests using `offset` / `limit`
- **Hard block at 2 MB**: forces use of partial reads or `Grep` to avoid burning context

Skips the check if `offset` or `limit` is already set.

### 📚 `session-summary.js`
**Fires:** `Stop`
**What it does:** Appends a structured session summary to `~/.claude/sessions/<date>-<session-id>.md`. Includes the working directory, current `git status --short`, and recent commit log.

Use case: search past sessions later (`grep -r "TimeoutError" ~/.claude/sessions/`) to find how you solved a problem the first time.

### 🧠 `mempal-session-start.sh`
**Fires:** `SessionStart`
**What it does:** If the [`mempalace`](https://github.com/marc-ai/mempalace) CLI is on `$PATH`, prints a compact palace status (drawer counts, top wings) plus the top 3 memories matching the current `cwd` repo basename — straight to stderr, so they appear as a system notice in the transcript. This gives every session an instant "what did we already know about this repo?" recap.

**Self-disables** when `mempalace` is not installed: `command -v mempalace` fails → `exit 0` immediately.

### 🧠 `mempal-stop.sh`
**Fires:** `Stop`
**What it does:** Pipes the Stop event payload to `mempalace hook run --hook stop --harness claude-code` (falling back to `python3 -m mempalace …` for older versions). The palace then mines what was learned in this session into searchable drawers, ready for the next `mempal-session-start.sh` to surface.

**Self-disables** when `mempalace` is not installed. Always re-emits stdin so other Stop hooks downstream see the original payload.

### 🧠 `mempal-precompact.sh`
**Fires:** `PreCompact`
**What it does:** Snapshots important context (active bug traces, in-progress PoCs, design decisions) into the palace right before Claude Code compresses the conversation. Stops valuable work from being lost to context squashing.

**Self-disables** when `mempalace` is not installed. Always re-emits stdin.

## Install

```bash
# 1. Copy hooks to ~/.claude/hooks/
cp hooks/*.js ~/.claude/hooks/
cp hooks/log-error.sh hooks/mempal-*.sh ~/.claude/hooks/
chmod +x ~/.claude/hooks/log-error.sh ~/.claude/hooks/mempal-*.sh

# 2. Copy the example settings
cp settings.example.json ~/.claude/settings.json

# 3. Restart Claude Code
```

## Disabling individual hooks

Each hook is wired separately in `settings.json`. To disable one, delete its entry from the matching `PreToolUse` / `PostToolUse` / `Stop` block.

Example — disable `cost-tracker`:
```json
"Stop": [
  {
    "matcher": "*",
    "hooks": [
      { "type": "command", "command": "node ~/.claude/hooks/batch-format.js", "timeout": 300 },
      { "type": "command", "command": "node ~/.claude/hooks/check-console.js" }
      // cost-tracker.js removed
    ]
  }
]
```

## Writing your own hook

Every hook follows the same pattern:

```js
// Read JSON input from stdin
let d = '';
process.stdin.on('data', c => d += c);
process.stdin.on('end', () => {
  try {
    const i = JSON.parse(d);
    // i.tool_name, i.tool_input, i.tool_output, etc. — depends on the event
    // ... your logic ...
    // To BLOCK: process.exit(2) with a message to stderr
    // To WARN: process.stderr.write(msg) and continue
  } catch (e) {}
  process.stdout.write(d); // Pass through the original input
});
```

See the [Claude Code hooks docs](https://docs.claude.com/en/docs/claude-code/hooks) for the full event payload schema.

## Safety Philosophy

These hooks assume `"defaultMode": "bypassPermissions"` — meaning Claude does not prompt for each tool call. Without the hooks, you would lose two layers of safety:

1. **The human prompt** — the "are you sure?" before each destructive operation
2. **The human eyes** — the chance to spot a hardcoded secret in a diff before it gets committed

The hooks try to replace both with **deterministic rules**. They will miss things (no heuristic is perfect), but they catch the most common failure modes: `rm -rf`, force-pushes to main, `--no-verify`, committed secrets, committed debuggers, edits to `.env`/`.pem`/credentials, and weakened linter configs.

Treat them as a safety net, not a replacement for review.
