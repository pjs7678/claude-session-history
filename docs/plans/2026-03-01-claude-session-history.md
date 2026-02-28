# claude-session-history Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build an open-source tool that adds per-session input history search for Claude Code inside tmux, using fzf for fuzzy selection.

**Architecture:** A SessionStart hook saves the current timestamp and project path into tmux environment variables per pane. When the user presses `prefix + H`, a shell script reads those env vars, passes them to a Python script that filters `~/.claude/history.jsonl` by matching sessionId, and displays results in a fzf-tmux popup. Selection copies to clipboard.

**Tech Stack:** Python 3 (stdlib only), Bash, tmux, fzf

---

## Task 1: Initialize Git Repo + Project Skeleton

**Files:**
- Create: `LICENSE`
- Create: `.gitignore`

**Step 1: Init git repo**

```bash
cd ~/dev/claude-session-history
git init
```

**Step 2: Create MIT LICENSE**

Create `LICENSE` with standard MIT license text, copyright 2026 jongsu.

**Step 3: Create .gitignore**

```
__pycache__/
*.pyc
.DS_Store
```

**Step 4: Commit**

```bash
git add LICENSE .gitignore
git commit -m "chore: init repo with LICENSE and .gitignore"
```

---

## Task 2: Implement `scripts/claude-history.py`

**Files:**
- Create: `scripts/claude-history.py`

This is the core logic. It reads `~/.claude/history.jsonl` and filters entries by sessionId.

**SessionId lookup algorithm:**
1. Read all entries from `history.jsonl`
2. Find the first entry where `timestamp >= start_ts` AND `project == project_path`
3. That entry's `sessionId` becomes the target
4. Return all entries with that `sessionId`

**Step 1: Create `scripts/claude-history.py`**

```python
#!/usr/bin/env python3
"""
Claude Code session history viewer.
Filters ~/.claude/history.jsonl by sessionId for the current tmux pane.

Usage:
  claude-history.py <start_timestamp_ms> <project_path>
  claude-history.py --all <project_path>
"""

import json
import sys
import os
from datetime import datetime


def load_history():
    """Load all entries from history.jsonl."""
    path = os.path.expanduser("~/.claude/history.jsonl")
    if not os.path.exists(path):
        return []
    entries = []
    with open(path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entries.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return entries


def find_session_id(entries, start_ts, project):
    """Find sessionId by matching start timestamp and project path."""
    for entry in entries:
        if entry.get("timestamp", 0) >= start_ts and entry.get("project") == project:
            return entry.get("sessionId")
    return None


def format_entry(entry):
    """Format a history entry as a single line with timestamp prefix."""
    ts = entry.get("timestamp", 0)
    dt = datetime.fromtimestamp(ts / 1000)
    time_str = dt.strftime("%Y-%m-%d %H:%M")
    display = entry.get("display", "")
    # Replace newlines with ↵ for single-line display
    display = display.replace("\n", " ↵ ")
    return f"[{time_str}] {display}"


def current_session_mode(start_ts, project):
    """Show history for the current session only."""
    entries = load_history()
    session_id = find_session_id(entries, int(start_ts), project)
    if not session_id:
        return
    for entry in entries:
        if entry.get("sessionId") == session_id:
            print(format_entry(entry))


def all_sessions_mode(project):
    """Show all sessions for a project, grouped by session, sorted by time."""
    entries = load_history()
    # Filter by project
    project_entries = [e for e in entries if e.get("project") == project]
    if not project_entries:
        return
    # Group by sessionId, preserving order
    sessions = {}
    for entry in project_entries:
        sid = entry.get("sessionId", "unknown")
        if sid not in sessions:
            sessions[sid] = []
        sessions[sid].append(entry)
    # Sort each session's entries by timestamp
    for sid in sessions:
        sessions[sid].sort(key=lambda e: e.get("timestamp", 0))
    # Sort sessions by their first entry's timestamp
    sorted_sessions = sorted(sessions.values(), key=lambda s: s[0].get("timestamp", 0))
    # Print all entries, sessions in chronological order
    for session_entries in sorted_sessions:
        for entry in session_entries:
            print(format_entry(entry))


def main():
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <start_timestamp_ms> <project_path>", file=sys.stderr)
        print(f"       {sys.argv[0]} --all <project_path>", file=sys.stderr)
        sys.exit(1)

    if sys.argv[1] == "--all":
        all_sessions_mode(sys.argv[2])
    else:
        current_session_mode(sys.argv[1], sys.argv[2])


if __name__ == "__main__":
    main()
```

**Step 2: Make executable and test manually**

```bash
chmod +x scripts/claude-history.py
# Test --all mode with a known project path:
python3 scripts/claude-history.py --all /Users/jongsu
# Should print formatted history entries
```

Expected: lines like `[2026-02-21 14:30] some input text`

**Step 3: Test single-session mode**

```bash
# Pick a known timestamp and project from history.jsonl to verify:
python3 scripts/claude-history.py 1769902229625 /Users/jongsu
# Should print entries from that specific session only
```

**Step 4: Commit**

```bash
git add scripts/claude-history.py
git commit -m "feat: add claude-history.py session history parser"
```

---

## Task 3: Implement `scripts/show-history.sh`

**Files:**
- Create: `scripts/show-history.sh`

**Step 1: Create `scripts/show-history.sh`**

```bash
#!/bin/bash
# Show Claude Code session history for the current tmux pane via fzf popup.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PANE_ID=$(tmux display-message -p '#{pane_id}' | tr -d '%')

START_TS=$(tmux showenv "CLAUDE_TS_${PANE_ID}" 2>/dev/null | cut -d= -f2-)
PROJECT_DIR=$(tmux showenv "CLAUDE_DIR_${PANE_ID}" 2>/dev/null | cut -d= -f2-)

if [ -z "$START_TS" ] || [ -z "$PROJECT_DIR" ]; then
    tmux display-message "No Claude Code session found in this pane."
    exit 0
fi

copy_to_clipboard() {
    if command -v pbcopy &>/dev/null; then
        pbcopy
    elif command -v xclip &>/dev/null; then
        xclip -selection clipboard
    elif command -v wl-copy &>/dev/null; then
        wl-copy
    else
        tmux load-buffer -
        tmux display-message "Copied to tmux buffer (paste: prefix + ])"
        return
    fi
    tmux display-message "Copied to clipboard"
}

HISTORY=$(python3 "$SCRIPT_DIR/claude-history.py" "$START_TS" "$PROJECT_DIR")

if [ -z "$HISTORY" ]; then
    tmux display-message "No history found for this session."
    exit 0
fi

SELECTED=$(echo "$HISTORY" | fzf-tmux -p 80%,50% --no-sort --tac \
    --prompt="Session history > " \
    --header="Enter: copy | Esc: cancel")

if [ -n "$SELECTED" ]; then
    # Strip the timestamp prefix: [YYYY-MM-DD HH:MM]
    INPUT="${SELECTED#\[????-??-?? ??:??\] }"
    # Restore newlines from ↵
    INPUT=$(echo "$INPUT" | sed 's/ ↵ /\n/g')
    echo -n "$INPUT" | copy_to_clipboard
fi
```

**Step 2: Make executable**

```bash
chmod +x scripts/show-history.sh
```

**Step 3: Commit**

```bash
git add scripts/show-history.sh
git commit -m "feat: add show-history.sh tmux keybinding handler"
```

---

## Task 4: Implement `install.sh`

**Files:**
- Create: `install.sh`

**Step 1: Create `install.sh`**

```bash
#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

ok() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; exit 1; }

# 1. Check dependencies
for cmd in tmux python3 fzf; do
    command -v "$cmd" &>/dev/null || fail "Required: $cmd not found. Please install it first."
done
ok "Dependencies: tmux, python3, fzf"

# 2. Check tmux session (warn only)
if [ -z "$TMUX" ]; then
    echo "  Note: Not inside a tmux session. Install will continue, but the tool requires tmux."
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="$HOME/.claude/scripts"

# 3. Install scripts
mkdir -p "$DEST_DIR"
for file in claude-history.py show-history.sh; do
    if [ -f "$DEST_DIR/$file" ]; then
        cp "$DEST_DIR/$file" "$DEST_DIR/${file}.bak"
    fi
    cp "$SCRIPT_DIR/scripts/$file" "$DEST_DIR/$file"
    chmod +x "$DEST_DIR/$file"
done
ok "Scripts installed to ~/.claude/scripts/"

# 4. Merge SessionStart hook into settings.json
SETTINGS_FILE="$HOME/.claude/settings.json"
HOOK_COMMAND='[ -n "$TMUX" ] && PANE_ID=$(tmux display-message -p '"'"'#{pane_id}'"'"' | tr -d '"'"'%'"'"') && tmux setenv "CLAUDE_TS_${PANE_ID}" "$(python3 -c '"'"'import time;print(int(time.time()*1000))'"'"')" && tmux setenv "CLAUDE_DIR_${PANE_ID}" "$(pwd)" || true'

python3 - "$SETTINGS_FILE" "$HOOK_COMMAND" << 'PYEOF'
import json
import sys
import os

settings_file = sys.argv[1]
hook_command = sys.argv[2]

# Read existing settings
if os.path.exists(settings_file):
    with open(settings_file, "r") as f:
        settings = json.load(f)
else:
    settings = {}

# Ensure hooks.SessionStart exists
hooks = settings.setdefault("hooks", {})
session_start = hooks.setdefault("SessionStart", [])

# Check if our hook already exists
new_hook_entry = {
    "matcher": "",
    "hooks": [{"type": "command", "command": hook_command}]
}

already_exists = False
for entry in session_start:
    for h in entry.get("hooks", []):
        if "CLAUDE_TS_" in h.get("command", ""):
            already_exists = True
            break

if not already_exists:
    # Backup
    if os.path.exists(settings_file):
        import shutil
        shutil.copy2(settings_file, settings_file + ".bak")
    session_start.append(new_hook_entry)
    with open(settings_file, "w") as f:
        json.dump(settings, f, indent=2)
        f.write("\n")

sys.exit(0 if not already_exists else 2)
PYEOF

if [ $? -eq 0 ]; then
    ok "SessionStart hook added to ~/.claude/settings.json"
elif [ $? -eq 2 ]; then
    ok "SessionStart hook already exists in ~/.claude/settings.json (skipped)"
fi

# 5. Add tmux keybinding
TMUX_CONF="$HOME/.tmux.conf"
BINDING="bind-key H run-shell 'bash ~/.claude/scripts/show-history.sh'"

if ! grep -qF "bind-key H" "$TMUX_CONF" 2>/dev/null; then
    echo "" >> "$TMUX_CONF"
    echo "# Claude Code session history (prefix + H)" >> "$TMUX_CONF"
    echo "$BINDING" >> "$TMUX_CONF"
    ok "Keybinding (prefix + H) added to ~/.tmux.conf"
else
    ok "Keybinding (prefix + H) already exists in ~/.tmux.conf (skipped)"
fi

# 6. Reload tmux config
if [ -n "$TMUX" ]; then
    tmux source-file "$TMUX_CONF" 2>/dev/null && ok "tmux config reloaded" || true
fi

echo ""
echo "Done! Start a new Claude Code session and press prefix + H to search history."
```

**Step 2: Make executable**

```bash
chmod +x install.sh
```

**Step 3: Commit**

```bash
git add install.sh
git commit -m "feat: add install.sh with settings.json merge and tmux keybinding setup"
```

---

## Task 5: Implement `uninstall.sh`

**Files:**
- Create: `uninstall.sh`

**Step 1: Create `uninstall.sh`**

```bash
#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

ok() { echo -e "${GREEN}✓${NC} $1"; }

# 1. Remove scripts
for file in claude-history.py show-history.sh; do
    rm -f "$HOME/.claude/scripts/$file"
done
ok "Scripts removed from ~/.claude/scripts/"

# 2. Remove SessionStart hook from settings.json
SETTINGS_FILE="$HOME/.claude/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
    python3 - "$SETTINGS_FILE" << 'PYEOF'
import json
import sys
import os
import shutil

settings_file = sys.argv[1]
with open(settings_file, "r") as f:
    settings = json.load(f)

session_start = settings.get("hooks", {}).get("SessionStart", [])
filtered = []
for entry in session_start:
    dominated_by_us = any("CLAUDE_TS_" in h.get("command", "") for h in entry.get("hooks", []))
    if not dominated_by_us:
        filtered.append(entry)

settings["hooks"]["SessionStart"] = filtered

# Clean up empty structures
if not settings["hooks"]["SessionStart"]:
    del settings["hooks"]["SessionStart"]
if not settings["hooks"]:
    del settings["hooks"]

shutil.copy2(settings_file, settings_file + ".bak")
with open(settings_file, "w") as f:
    json.dump(settings, f, indent=2)
    f.write("\n")
PYEOF
    ok "SessionStart hook removed from ~/.claude/settings.json"
fi

# 3. Remove tmux keybinding
TMUX_CONF="$HOME/.tmux.conf"
if [ -f "$TMUX_CONF" ]; then
    sed -i.bak '/# Claude Code session history/d' "$TMUX_CONF"
    sed -i.bak '/bind-key H.*show-history\.sh/d' "$TMUX_CONF"
    rm -f "${TMUX_CONF}.bak"
    ok "Keybinding removed from ~/.tmux.conf"
fi

# 4. Clean tmux env vars
if [ -n "$TMUX" ]; then
    tmux showenv -g 2>/dev/null | grep -E "^CLAUDE_(TS|DIR)_" | cut -d= -f1 | while read -r var; do
        tmux setenv -gu "$var" 2>/dev/null || true
    done
    tmux source-file "$TMUX_CONF" 2>/dev/null || true
    ok "tmux environment cleaned"
fi

echo ""
echo "Done! claude-session-history has been uninstalled."
```

**Step 2: Make executable**

```bash
chmod +x uninstall.sh
```

**Step 3: Commit**

```bash
git add uninstall.sh
git commit -m "feat: add uninstall.sh for clean removal"
```

---

## Task 6: Create README.md

**Files:**
- Create: `README.md`

**Step 1: Create README.md**

Content per the spec:
- Title + one-liner description
- Problem section referencing GitHub issues
- "How it works" diagram
- Requirements (Claude Code CLI, tmux, Python 3, fzf)
- Install instructions (curl one-liner + git clone)
- Usage (prefix + H, Enter to copy, Esc to cancel)
- Uninstall
- MIT License mention

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README"
```

---

## Task 7: Create GitHub Repo + Push

**Step 1: Create GitHub repo**

```bash
cd ~/dev/claude-session-history
gh repo create claude-session-history --public --source=. --push --description "Per-session input history search for Claude Code + tmux"
```

**Step 2: Verify**

```bash
gh repo view --web
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Git init + LICENSE + .gitignore | `LICENSE`, `.gitignore` |
| 2 | History parser (Python) | `scripts/claude-history.py` |
| 3 | tmux popup handler (Bash) | `scripts/show-history.sh` |
| 4 | Install script | `install.sh` |
| 5 | Uninstall script | `uninstall.sh` |
| 6 | README | `README.md` |
| 7 | GitHub repo + push | — |
