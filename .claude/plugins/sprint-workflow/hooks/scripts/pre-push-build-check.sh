#!/bin/bash
set -euo pipefail

input=$(cat)
tool_input=$(echo "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)

# Only intercept git push commands
if ! echo "$tool_input" | grep -q "git push"; then
  echo '{}'
  exit 0
fi

echo '{"systemMessage": "PUSH GATE: Before pushing, ensure all builds and type-checks pass. Run the project build command now if not already verified."}'
exit 0
