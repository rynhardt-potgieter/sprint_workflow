#!/bin/bash
# Stop hook: nags about sprint tracking ONLY when a sprint is active.
# Active = .claude/.sprint-active sentinel file exists in the project root.
# Must ALWAYS exit 0 and output valid JSON — never crash the hook pipeline.

# Read stdin (Claude Code passes a JSON envelope; we don't need it but must drain it)
input=$(cat 2>/dev/null || true)

# Find the project root. Prefer git toplevel; fall back to CWD.
project_root=""
if command -v git >/dev/null 2>&1; then
  project_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
fi
if [ -z "$project_root" ]; then
  project_root="$PWD"
fi

sentinel="$project_root/.claude/.sprint-active"

# No sprint in progress → silent pass-through. This is the common case.
if [ ! -f "$sentinel" ]; then
  echo '{}'
  exit 0
fi

# Sprint is active. Three layers of loop protection:
#   1. We use hookSpecificOutput.additionalContext (NOT decision:"block").
#      Stop is never blocked — the user is returned to prompt; reminder lands
#      on the NEXT user-initiated turn. No forced re-loop.
#   2. Rate-limit by wall-clock: skip if we already fired within RATE_LIMIT_S.
#      "Once per session" was too quiet; "every Stop" was too noisy.
#   3. The message body explicitly tells the agent NOT to ack — it should
#      either perform tool calls or stay silent. No ack text = no second Stop.

# Rate limit between hook fires within a single session.
# Override by setting SPRINT_STOP_HOOK_RATE_LIMIT_S in your shell env or
# in .claude/settings.local.json under "env". Default: 600s (10 minutes).
# Set to 0 to fire on every Stop. Cross-session first-fire is unaffected.
RATE_LIMIT_S="${SPRINT_STOP_HOOK_RATE_LIMIT_S:-600}"
case "$RATE_LIMIT_S" in *[!0-9]*|"") RATE_LIMIT_S=600 ;; esac

# Extract session_id from stdin envelope. New sessions ALWAYS fire on first
# Stop regardless of rate limit — that's how a brand-new session resuming
# a sprint gets reminded immediately instead of being silenced by stale state
# from a prior session.
session_id=""
if command -v node >/dev/null 2>&1; then
  session_id=$(node -e "try{const j=JSON.parse(process.argv[1]);console.log(j.session_id||'')}catch(e){console.log('')}" "$input" 2>/dev/null || true)
fi

last_fire_file="$project_root/.claude/.sprint-active.last-fire"
now=$(date +%s 2>/dev/null || echo 0)
last_session=""
last_fire=0
if [ -f "$last_fire_file" ]; then
  # File format: "<session_id>\t<unix_ts>" (tab-separated)
  last_session=$(awk -F'\t' 'NR==1{print $1}' "$last_fire_file" 2>/dev/null || true)
  last_fire=$(awk -F'\t' 'NR==1{print $2}' "$last_fire_file" 2>/dev/null || echo 0)
  case "$last_fire" in *[!0-9]*|"") last_fire=0 ;; esac
fi

# Only rate-limit if we're in the SAME session. Different session = fire now.
if [ -n "$session_id" ] && [ "$session_id" = "$last_session" ] \
   && [ "$now" -gt 0 ] && [ "$last_fire" -gt 0 ]; then
  delta=$((now - last_fire))
  if [ "$delta" -lt "$RATE_LIMIT_S" ]; then
    echo '{}'
    exit 0
  fi
fi

# Record this fire (session + timestamp).
if [ "$now" -gt 0 ]; then
  printf '%s\t%s\n' "$session_id" "$now" > "$last_fire_file" 2>/dev/null || true
fi

# Read tracking source from sentinel (first line: "linear" or "md")
tracking_source=""
if [ -r "$sentinel" ]; then
  tracking_source=$(head -n1 "$sentinel" 2>/dev/null || true)
fi

case "$tracking_source" in
  linear)
    msg="SPRINT ACTIVE (Linear). For every task you touched this turn that is now functionally complete: (1) save_issue → transition status to In Review or Done, (2) save_comment with files changed + outcome. For deferred items: save_issue a new sub-task under the same Epic OR save_comment on an upcoming task in the sprint — never just comment on the closing task (those comments are not re-read by future dispatches)."
    ;;
  md)
    msg="SPRINT ACTIVE (markdown plan). For every story/task you touched this turn: update its status field and checklists. For deferred items: add a new task entry to the plan OR record them in the plan's Carryover section — do not just append a note under the completed task."
    ;;
  *)
    msg="SPRINT ACTIVE. Reconcile sprint tracking (Linear or markdown plan) for every task touched this turn — statuses, completion notes. Route deferred items to a new task or upcoming task, not as comments on the closing task."
    ;;
esac

# NOTE: Stop hooks do not support hookSpecificOutput.additionalContext (that
# field is only valid on SessionStart / UserPromptSubmit / PreToolUse /
# PostToolUse / PostToolBatch). Stop hooks accept only top-level fields:
# continue, suppressOutput, stopReason, decision, reason, systemMessage.
#
# `systemMessage` is UI-visible to the user but NOT injected into the agent's
# context — the agent will not re-read it on the next turn. This means the
# user sees the reminder and can nudge the agent. To get the agent itself to
# see a sprint reminder, the proper mechanism is a SessionStart hook (separate
# script) using its additionalContext field. This file deliberately uses
# systemMessage to avoid the block/loop pattern that bit earlier versions.
escaped=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '{"systemMessage":"%s"}\n' "$escaped"
exit 0
