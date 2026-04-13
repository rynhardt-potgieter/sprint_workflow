#!/bin/bash
# Pre-tool-use hook: reminds to build-check before git push.
# Must ALWAYS exit 0 and output valid JSON — never crash the hook pipeline.

# Read all stdin first
input=$(cat 2>/dev/null || true)

# Parse command using node (guaranteed by Claude Code). Fall back gracefully.
tool_command=""
if command -v node >/dev/null 2>&1; then
  tool_command=$(node -e "try{const j=JSON.parse(process.argv[1]);console.log(j.tool_input?.command||'')}catch(e){console.log('')}" "$input" 2>/dev/null || true)
fi

# If we couldn't parse or it's not a push, pass through
if [ -z "$tool_command" ]; then
  echo '{}'
  exit 0
fi

# Only intercept git push commands
case "$tool_command" in
  *"git push"*)
    echo '{"systemMessage": "PUSH GATE: Before pushing, ensure all builds and type-checks pass. Run the project build command now if not already verified."}'
    ;;
  *)
    echo '{}'
    ;;
esac

exit 0
