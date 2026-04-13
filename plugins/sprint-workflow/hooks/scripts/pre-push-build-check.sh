#!/bin/bash
set -euo pipefail

# Read hook input from stdin, parse with node (cross-platform, no jq dependency)
tool_command=$(node -e "
let d='';
process.stdin.on('data',c=>d+=c);
process.stdin.on('end',()=>{
  try{const j=JSON.parse(d);console.log(j.tool_input?.command||'')}
  catch(e){console.log('')}
});
" 2>/dev/null || echo "")

# Only intercept git push commands
if ! echo "$tool_command" | grep -q "git push"; then
  echo '{}'
  exit 0
fi

echo '{"systemMessage": "PUSH GATE: Before pushing, ensure all builds and type-checks pass. Run the project build command now if not already verified."}'
exit 0
