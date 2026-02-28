#!/usr/bin/env bash
set -e

GREEN='\033[0;32m'
NC='\033[0m' # No Color

INSTALL_DIR="$HOME/.claude/scripts"

# ---------------------------------------------------------------------------
# 1. Remove scripts
# ---------------------------------------------------------------------------
rm -f "$INSTALL_DIR/claude-history.py"
rm -f "$INSTALL_DIR/show-history.sh"

echo -e "${GREEN}✓ Scripts removed from ~/.claude/scripts/${NC}"

# ---------------------------------------------------------------------------
# 2. Remove SessionStart hook from settings.json
# ---------------------------------------------------------------------------
SETTINGS_FILE="$HOME/.claude/settings.json"

if [ -f "$SETTINGS_FILE" ]; then
  python3 - "$SETTINGS_FILE" <<'PYEOF'
import json
import os
import sys

settings_path = sys.argv[1]

with open(settings_path, "r") as f:
    settings = json.load(f)

hooks = settings.get("hooks", {})
session_start = hooks.get("SessionStart", [])

if session_start:
    # Filter out entries where any hook command contains CLAUDE_TS_
    filtered = []
    for entry in session_start:
        is_ours = False
        for hook in entry.get("hooks", []):
            if "CLAUDE_TS_" in hook.get("command", ""):
                is_ours = True
                break
        if not is_ours:
            filtered.append(entry)

    if filtered:
        hooks["SessionStart"] = filtered
    else:
        hooks.pop("SessionStart", None)

    if not hooks:
        settings.pop("hooks", None)

    # Backup before writing
    with open(settings_path, "r") as f:
        backup_content = f.read()
    with open(settings_path + ".bak", "w") as f:
        f.write(backup_content)

    with open(settings_path, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")
PYEOF
fi

echo -e "${GREEN}✓ SessionStart hook removed from ~/.claude/settings.json${NC}"

# ---------------------------------------------------------------------------
# 3. Remove tmux keybinding from ~/.tmux.conf
# ---------------------------------------------------------------------------
TMUX_CONF="$HOME/.tmux.conf"

if [ -f "$TMUX_CONF" ]; then
  python3 - "$TMUX_CONF" <<'PYEOF'
import sys

tmux_conf = sys.argv[1]

with open(tmux_conf, "r") as f:
    lines = f.readlines()

filtered = []
for line in lines:
    # Skip the comment line
    if line.strip() == "# Claude Code session history (prefix + H)":
        continue
    # Skip the binding line containing both bind-key H and show-history.sh
    if "bind-key H" in line and "show-history.sh" in line:
        continue
    filtered.append(line)

# Remove trailing blank lines that may have been left behind
while filtered and filtered[-1].strip() == "":
    filtered.pop()

# Add a final newline if there's content
if filtered:
    # Ensure last line ends with newline
    if not filtered[-1].endswith("\n"):
        filtered[-1] += "\n"

with open(tmux_conf, "w") as f:
    f.writelines(filtered)
PYEOF
fi

echo -e "${GREEN}✓ Keybinding removed from ~/.tmux.conf${NC}"

# ---------------------------------------------------------------------------
# 4. Clean tmux environment variables
# ---------------------------------------------------------------------------
if [ -n "$TMUX" ]; then
  tmux showenv 2>/dev/null | while IFS= read -r line; do
    case "$line" in
      CLAUDE_TS_*|CLAUDE_DIR_*)
        var="${line%%=*}"
        tmux setenv -gu "$var"
        ;;
    esac
  done
fi

echo -e "${GREEN}✓ tmux environment cleaned${NC}"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "Done! claude-session-history has been uninstalled."
