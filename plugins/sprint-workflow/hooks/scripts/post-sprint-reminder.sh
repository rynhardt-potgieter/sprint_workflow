#!/bin/bash
# PostToolUse hook: reminds the agent to reconcile sprint tracking after
# meaningful work. Uses hookSpecificOutput.additionalContext which IS supported
# on PostToolUse (unlike Stop), so the reminder lands in the agent's context
# and the agent actually reads it.
#
# Gated on .claude/.sprint-active sentinel so it stays silent outside sprints.
# Rate-limited via SPRINT_STOP_HOOK_RATE_LIMIT_S (default 600s = 10 min) and
# the shared .sprint-active.last-fire file, so the user does not get nagged
# after every single Edit during active sprint work.
#
# Must ALWAYS exit 0 and output valid JSON — never crash the hook pipeline.

input=$(cat 2>/dev/null || true)

# Find project root.
project_root=""
if command -v git >/dev/null 2>&1; then
  project_root=$(git rev-parse --show-toplevel 2>/dev/null || true)
fi
if [ -z "$project_root" ]; then
  project_root="$PWD"
fi

sentinel="$project_root/.claude/.sprint-active"

# No sprint → silent pass-through.
if [ ! -f "$sentinel" ]; then
  echo '{}'
  exit 0
fi

# Rate limit: shared with the Stop hook via .sprint-active.last-fire.
# Same env var (SPRINT_STOP_HOOK_RATE_LIMIT_S) controls both, so a single
# project setting governs sprint nag frequency.
RATE_LIMIT_S="${SPRINT_STOP_HOOK_RATE_LIMIT_S:-600}"
case "$RATE_LIMIT_S" in *[!0-9]*|"") RATE_LIMIT_S=600 ;; esac

session_id=""
if command -v node >/dev/null 2>&1; then
  session_id=$(node -e "try{const j=JSON.parse(process.argv[1]);console.log(j.session_id||'')}catch(e){console.log('')}" "$input" 2>/dev/null || true)
fi

last_fire_file="$project_root/.claude/.sprint-active.last-fire"
now=$(date +%s 2>/dev/null || echo 0)
last_session=""
last_fire=0
if [ -f "$last_fire_file" ]; then
  last_session=$(awk -F'\t' 'NR==1{print $1}' "$last_fire_file" 2>/dev/null || true)
  last_fire=$(awk -F'\t' 'NR==1{print $2}' "$last_fire_file" 2>/dev/null || echo 0)
  case "$last_fire" in *[!0-9]*|"") last_fire=0 ;; esac
fi

# Same-session rate limit. New sessions always fire on first eligible tool call.
if [ -n "$session_id" ] && [ "$session_id" = "$last_session" ] \
   && [ "$now" -gt 0 ] && [ "$last_fire" -gt 0 ]; then
  delta=$((now - last_fire))
  if [ "$delta" -lt "$RATE_LIMIT_S" ]; then
    echo '{}'
    exit 0
  fi
fi

# Record this fire.
if [ "$now" -gt 0 ]; then
  printf '%s\t%s\n' "$session_id" "$now" > "$last_fire_file" 2>/dev/null || true
fi

# Read tracking source from sentinel.
tracking_source=""
if [ -r "$sentinel" ]; then
  tracking_source=$(head -n1 "$sentinel" 2>/dev/null || true)
fi

case "$tracking_source" in
  linear)
    msg="Sprint reminder (Linear tracking active): when you finish the current task, transition its Linear status via save_issue (In Progress → In Review or Done) and post a save_comment with files changed + outcome. For any items you defer or push out of scope, post a save_comment on the originating task tagged [DEFERRED] so the next dispatch picks it up. The Linear board, not your chat output, is the source of truth — keep it current."
    ;;
  md)
    msg="Sprint reminder (markdown plan active): when you finish the current task, update its status field and checklists in the plan document, and record any deferred items in the plan's Carryover section so the next dispatch picks them up. The plan document, not your chat output, is the source of truth — keep it current."
    ;;
  *)
    msg="Sprint reminder: sprint tracking (Linear or markdown plan) needs to be reconciled when the current task completes — status transition, completion note, and any deferred items recorded. The tracker, not your chat output, is the source of truth."
    ;;
esac

# PostToolUse supports hookSpecificOutput.additionalContext (per Claude Code
# hook schema), so the message lands in the agent's context. Escape for JSON.
escaped=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')
printf '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"%s"}}\n' "$escaped"
exit 0
