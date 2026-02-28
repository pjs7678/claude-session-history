# claude-session-history

Per-session input history search for Claude Code + tmux.

Press `prefix + H` to search your input history scoped to the current Claude Code session.

<!-- TODO: demo.gif -->

## Problem

Claude Code shares input history (up arrow) across all sessions. When using multiple sessions simultaneously, finding previous inputs becomes difficult.

See: [anthropics/claude-code#15631](https://github.com/anthropics/claude-code/issues/15631)

## How it works

```
1. Claude Code session starts
   └─ SessionStart hook saves (timestamp, project) to tmux env vars

2. User presses prefix + H
   └─ show-history.sh reads CLAUDE_TS_* and CLAUDE_DIR_* from tmux env

3. claude-history.py finds the sessionId
   └─ Matches timestamp + project against ~/.claude/history.jsonl

4. Filtered results shown in fzf-tmux popup
   └─ Only inputs from the current session, sorted chronologically

5. Enter → copies selection to clipboard
```

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
- tmux
- Python 3
- fzf

## Install

Clone and run the install script:

```sh
git clone https://github.com/pjs7678/claude-session-history.git
cd claude-session-history
./install.sh
```

The installer will:
- Copy scripts to `~/.claude/scripts/`
- Add a `SessionStart` hook to `~/.claude/settings.json`
- Add a `prefix + H` keybinding to `~/.tmux.conf`

Or manually copy the files and configure them yourself -- see `install.sh` for details.

## Usage

- `prefix + H` -- search current session history (fzf popup)
- `Enter` -- copy selected item to clipboard
- `Esc` -- cancel

## Uninstall

```sh
./uninstall.sh
```

## License

MIT
