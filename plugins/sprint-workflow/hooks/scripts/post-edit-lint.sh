#!/bin/bash
set -euo pipefail

# Read hook input from stdin, parse with node (cross-platform, no jq dependency)
file_path=$(node -e "
let d='';
process.stdin.on('data',c=>d+=c);
process.stdin.on('end',()=>{
  try{const j=JSON.parse(d);console.log(j.tool_input?.file_path||j.tool_input?.filePath||'')}
  catch(e){console.log('')}
});
" 2>/dev/null || echo "")

if [ -z "$file_path" ] || [ "$file_path" = "undefined" ]; then
  echo '{}'
  exit 0
fi

# Provide type-check reminders based on file extension
case "$file_path" in
  *.cs)
    echo '{"systemMessage": "C# file edited. Run `dotnet build` to verify after completing this change batch."}'
    ;;
  *.ts|*.tsx)
    echo '{"systemMessage": "TypeScript file edited. Run `npx tsc --noEmit` to verify types after completing this change batch."}'
    ;;
  *.py)
    echo '{"systemMessage": "Python file edited. Run type checker and tests after completing this change batch."}'
    ;;
  *.go)
    echo '{"systemMessage": "Go file edited. Run `go build ./...` to verify after completing this change batch."}'
    ;;
  *.rs)
    echo '{"systemMessage": "Rust file edited. Run `cargo check` to verify after completing this change batch."}'
    ;;
  *)
    echo '{}'
    ;;
esac

exit 0
