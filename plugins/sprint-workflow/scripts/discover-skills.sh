#!/usr/bin/env bash
# Discovers skill files for the current project.
# Priority: project-local (.claude/skills/) > plugin-bundled skills
# Output: structured list of skill paths with names and source labels
#
# The plugin root is derived from THIS script's location (scripts/ is one
# level below the plugin root). This works regardless of how the script
# is invoked — from commands, hooks, or directly.

set -euo pipefail

# Derive plugin root from this script's own location — reliable everywhere
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

PROJECT_ROOT="$(pwd)"
LOCAL_FOUND=0
GLOBAL_FOUND=0

echo "## Discovered Skills"
echo ""

# --- Phase 1: Project-local skills ---
LOCAL_SKILLS_DIR="${PROJECT_ROOT}/.claude/skills"
if [ -d "$LOCAL_SKILLS_DIR" ]; then
  SKILLS=$(find "$LOCAL_SKILLS_DIR" -name "SKILL.md" -type f 2>/dev/null | sort)
  if [ -n "$SKILLS" ]; then
    LOCAL_FOUND=1
    echo "### Project-Local Skills (PRIMARY — these take priority)"
    echo ""
    while IFS= read -r skill_path; do
      skill_name=$(basename "$(dirname "$skill_path")")
      desc=$(sed -n '/^description:/{ s/^description: *"\{0,1\}//; s/"\{0,1\} *$//; p; q; }' "$skill_path" 2>/dev/null || echo "")
      desc_short=$(echo "$desc" | head -c 120)
      echo "- **${skill_name}**: \`${skill_path}\`"
      if [ -n "$desc_short" ]; then
        echo "  ${desc_short}"
      fi
    done <<< "$SKILLS"
    echo ""
  fi
fi

# --- Phase 2: Plugin-bundled skills ---
# Derived from this script's own location — always correct
PLUGIN_SKILLS_DIR="${PLUGIN_ROOT}/skills"

if [ -d "$PLUGIN_SKILLS_DIR" ]; then
  SKILLS=$(find "$PLUGIN_SKILLS_DIR" -name "SKILL.md" -type f 2>/dev/null | sort)
  if [ -n "$SKILLS" ]; then
    GLOBAL_FOUND=1
    if [ "$LOCAL_FOUND" -eq 1 ]; then
      echo "### Plugin Engineering Standards (SUPPLEMENTARY — use when no local equivalent exists)"
    else
      echo "### Plugin Engineering Standards (PRIMARY — no project-local skills found)"
    fi
    echo ""
    while IFS= read -r skill_path; do
      skill_name=$(basename "$(dirname "$skill_path")")
      # Skip task-board-ops from the listing (it's an operational skill, not an engineering standard)
      if [ "$skill_name" = "task-board-ops" ]; then
        continue
      fi
      desc=$(sed -n '/^description:/{ s/^description: *"\{0,1\}//; s/"\{0,1\} *$//; p; q; }' "$skill_path" 2>/dev/null || echo "")
      desc_short=$(echo "$desc" | head -c 120)
      echo "- **${skill_name}**: \`${skill_path}\`"
      if [ -n "$desc_short" ]; then
        echo "  ${desc_short}"
      fi
    done <<< "$SKILLS"
    echo ""
  fi
fi

# --- Phase 3: Summary ---
echo "### Skill Priority"
if [ "$LOCAL_FOUND" -eq 1 ] && [ "$GLOBAL_FOUND" -eq 1 ]; then
  echo "**MIXED**: Project has local skills AND plugin standards. Agents MUST read local skills first. Use plugin standards only for domains not covered locally."
elif [ "$LOCAL_FOUND" -eq 1 ]; then
  echo "**LOCAL ONLY**: Project has its own skills. Agents MUST read these."
elif [ "$GLOBAL_FOUND" -eq 1 ]; then
  echo "**PLUGIN ONLY**: No project-local skills. Agents MUST read the relevant plugin-bundled skills."
else
  echo "**NONE**: No skills found. Agents should follow CLAUDE.md conventions and general best practices."
fi
