#!/bin/bash
# show-history.sh — tmux keybinding handler that shows Claude Code session
# history in an fzf popup. Bound to prefix + H.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Cross-platform clipboard -------------------------------------------
copy_to_clipboard() {
  if command -v pbcopy &>/dev/null; then
    pbcopy
    tmux display-message "Copied to clipboard"
  elif [ -n "$DISPLAY" ] && command -v xclip &>/dev/null; then
    xclip -selection clipboard
    tmux display-message "Copied to clipboard"
  elif [ -n "$WAYLAND_DISPLAY" ] && command -v wl-copy &>/dev/null; then
    wl-copy
    tmux display-message "Copied to clipboard"
  else
    tmux load-buffer -
    tmux display-message "Copied to tmux buffer (paste: prefix + ])"
  fi
}

# --- Get pane info -------------------------------------------------------
pane_id=$(tmux display-message -p '#{pane_id}' | tr -d '%')

# --- Read tmux environment variables ------------------------------------
start_ts=$(tmux show-environment "CLAUDE_TS_${pane_id}" 2>/dev/null | cut -d= -f2-)
project_dir=$(tmux show-environment "CLAUDE_DIR_${pane_id}" 2>/dev/null | cut -d= -f2-)

if [ -z "$start_ts" ] || [ -z "$project_dir" ]; then
  tmux display-message "No Claude Code session found in this pane."
  exit 0
fi

# --- Fetch history -------------------------------------------------------
history=$(python3 "$SCRIPT_DIR/claude-history.py" "$start_ts" "$project_dir")

if [ -z "$history" ]; then
  tmux display-message "No history found for this session."
  exit 0
fi

# --- Show in fzf popup ---------------------------------------------------
selected=$(echo "$history" | fzf-tmux -p 80%,50% \
  --no-sort \
  --tac \
  --prompt "Session history > " \
  --header "Enter: copy | Esc: cancel")

if [ -n "$selected" ]; then
  # Strip timestamp prefix [YYYY-MM-DD HH:MM] and restore newlines
  cleaned=$(echo "$selected" | sed 's/^\[[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9]\{2\}:[0-9]\{2\}\] //')
  # Restore ↵ markers back to actual newlines
  restored=$(echo "$cleaned" | sed 's/ ↵ /\n/g')
  echo "$restored" | copy_to_clipboard
fi
