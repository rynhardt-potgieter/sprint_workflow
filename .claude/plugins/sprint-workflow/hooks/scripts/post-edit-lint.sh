#!/bin/bash
set -euo pipefail

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.filePath // ""' 2>/dev/null)

if [ -z "$file_path" ] || [ "$file_path" = "null" ]; then
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
