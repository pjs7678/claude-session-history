#!/usr/bin/env bash
set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.claude/scripts"

# ---------------------------------------------------------------------------
# 1. Check dependencies
# ---------------------------------------------------------------------------
missing=()
for cmd in tmux python3 fzf; do
  if ! command -v "$cmd" &>/dev/null; then
    missing+=("$cmd")
  fi
done

if [ ${#missing[@]} -ne 0 ]; then
  echo -e "${RED}✗ Missing dependencies: ${missing[*]}${NC}"
  echo "  Please install them and re-run this script."
  exit 1
fi
echo -e "${GREEN}✓ Dependencies: tmux, python3, fzf${NC}"

# ---------------------------------------------------------------------------
# 2. Check tmux session (warn only)
# ---------------------------------------------------------------------------
if [ -z "$TMUX" ]; then
  echo -e "  Note: You are not inside a tmux session. The keybinding will take"
  echo -e "  effect the next time you start or attach to a tmux session."
fi

# ---------------------------------------------------------------------------
# 3. Install scripts
# ---------------------------------------------------------------------------
mkdir -p "$INSTALL_DIR"

for file in claude-history.py show-history.sh; do
  dest="$INSTALL_DIR/$file"
  if [ -f "$dest" ]; then
    cp "$dest" "${dest}.bak"
  fi
  cp "$SCRIPT_DIR/scripts/$file" "$dest"
  chmod +x "$dest"
done

echo -e "${GREEN}✓ Scripts installed to ~/.claude/scripts/${NC}"

# ---------------------------------------------------------------------------
# 4. Merge SessionStart hook into ~/.claude/settings.json
# ---------------------------------------------------------------------------
SETTINGS_FILE="$HOME/.claude/settings.json"

RESULT_FILE=$(mktemp)
trap 'rm -f "$RESULT_FILE"' EXIT

python3 - "$SETTINGS_FILE" "$RESULT_FILE" <<'PYEOF'
import json
import os
import sys

settings_path = sys.argv[1]
result_file = sys.argv[2]

# Read existing settings or start fresh
if os.path.isfile(settings_path):
    with open(settings_path, "r") as f:
        settings = json.load(f)
else:
    settings = {}

# Ensure hooks.SessionStart array exists
hooks = settings.setdefault("hooks", {})
session_start = hooks.setdefault("SessionStart", [])

# Check if our hook already exists (look for CLAUDE_TS_ in any command)
already_exists = False
for entry in session_start:
    for hook in entry.get("hooks", []):
        if "CLAUDE_TS_" in hook.get("command", ""):
            already_exists = True
            break
    if already_exists:
        break

if already_exists:
    with open(result_file, "w") as f:
        f.write("skip")
else:
    # Backup existing settings.json
    if os.path.isfile(settings_path):
        import shutil
        shutil.copy2(settings_path, settings_path + ".bak")

    # Append our hook entry
    hook_command = (
        '[ -n "$TMUX" ] && '
        "PANE_ID=$(tmux display-message -p '#{pane_id}' | tr -d '%') && "
        'tmux setenv "CLAUDE_TS_${PANE_ID}" '
        '"$(python3 -c \'import time;print(int(time.time()*1000))\')" && '
        'tmux setenv "CLAUDE_DIR_${PANE_ID}" "$(pwd)" '
        '|| true'
    )
    hook_entry = {
        "matcher": "",
        "hooks": [{"type": "command", "command": hook_command}]
    }
    session_start.append(hook_entry)

    with open(settings_path, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")

    with open(result_file, "w") as f:
        f.write("added")
PYEOF

HOOK_ADDED=$(cat "$RESULT_FILE")

if [ "$HOOK_ADDED" = "added" ]; then
  echo -e "${GREEN}✓ SessionStart hook added to ~/.claude/settings.json${NC}"
else
  echo -e "${GREEN}✓ SessionStart hook already exists (skipped)${NC}"
fi

# ---------------------------------------------------------------------------
# 5. Add tmux keybinding
# ---------------------------------------------------------------------------
TMUX_CONF="$HOME/.tmux.conf"

if [ -f "$TMUX_CONF" ] && grep -q 'bind-key H' "$TMUX_CONF"; then
  echo -e "${GREEN}✓ Keybinding (prefix + H) already exists (skipped)${NC}"
else
  {
    echo ""
    echo "# Claude Code session history (prefix + H)"
    echo "bind-key H run-shell 'bash ~/.claude/scripts/show-history.sh'"
  } >> "$TMUX_CONF"
  echo -e "${GREEN}✓ Keybinding (prefix + H) added to ~/.tmux.conf${NC}"
fi

# ---------------------------------------------------------------------------
# 6. Reload tmux config
# ---------------------------------------------------------------------------
if [ -n "$TMUX" ]; then
  tmux source-file "$TMUX_CONF"
  echo -e "${GREEN}✓ tmux config reloaded${NC}"
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo "Done! Start a new Claude Code session and press prefix + H to search history."
