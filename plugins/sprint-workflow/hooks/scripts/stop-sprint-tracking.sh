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

# Sprint is active. Nag once per session by recording the session id we last
# nagged for. Session id is in the stdin envelope as `session_id`.
session_id=""
if command -v node >/dev/null 2>&1; then
  session_id=$(node -e "try{const j=JSON.parse(process.argv[1]);console.log(j.session_id||'')}catch(e){console.log('')}" "$input" 2>/dev/null || true)
fi

last_nagged_file="$project_root/.claude/.sprint-active.last-nag"
last_nagged=""
if [ -f "$last_nagged_file" ]; then
  last_nagged=$(cat "$last_nagged_file" 2>/dev/null || true)
fi

if [ -n "$session_id" ] && [ "$session_id" = "$last_nagged" ]; then
  # Already reminded this session. Stay silent so we don't loop.
  echo '{}'
  exit 0
fi

# Record this session so we don't nag again on subsequent Stop events.
if [ -n "$session_id" ]; then
  echo "$session_id" > "$last_nagged_file" 2>/dev/null || true
fi

# Read tracking source from sentinel (first line: "linear" or "md")
tracking_source=""
if [ -r "$sentinel" ]; then
  tracking_source=$(head -n1 "$sentinel" 2>/dev/null || true)
fi

case "$tracking_source" in
  linear)
    msg="SPRINT ACTIVE — before ending: verify all Linear tasks worked on this session are transitioned (In Progress → In Review or Done). Sentinel: .claude/.sprint-active"
    ;;
  md)
    msg="SPRINT ACTIVE — before ending: verify the plan markdown checklists/status fields are updated for every story/task touched this session. Sentinel: .claude/.sprint-active"
    ;;
  *)
    msg="SPRINT ACTIVE — before ending: verify sprint tracking (Linear or markdown plan) is up to date for every task touched this session. Sentinel: .claude/.sprint-active"
    ;;
esac

# Use systemMessage (informational) rather than block — never gates Stop, never loops.
printf '{"systemMessage": "%s"}\n' "$msg"
exit 0
