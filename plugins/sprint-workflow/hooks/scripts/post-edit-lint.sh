#!/bin/bash
# Post-edit hook: reminds to type-check after editing language-specific files.
# Must ALWAYS exit 0 and output valid JSON — never crash the hook pipeline.

# Read all stdin first
input=$(cat 2>/dev/null || true)

# Parse file_path using node (guaranteed by Claude Code). Fall back gracefully.
file_path=""
if command -v node >/dev/null 2>&1; then
  file_path=$(node -e "try{const j=JSON.parse(process.argv[1]);console.log(j.tool_input?.file_path||j.tool_input?.filePath||'')}catch(e){console.log('')}" "$input" 2>/dev/null || true)
fi

# If we couldn't parse, just pass through
if [ -z "$file_path" ] || [ "$file_path" = "undefined" ] || [ "$file_path" = "null" ]; then
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
