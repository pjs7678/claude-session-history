#!/usr/bin/env python3
"""Read ~/.claude/history.jsonl and filter by sessionId.

Two modes:
  Single-session: claude-history.py <start_timestamp_ms> <project_path>
  All-sessions:   claude-history.py --all <project_path>
"""

import json
import os
import sys
from datetime import datetime, timezone


HISTORY_FILE = os.path.expanduser("~/.claude/history.jsonl")


def load_entries():
    """Load all entries from history.jsonl, skipping malformed lines."""
    if not os.path.exists(HISTORY_FILE):
        return []
    entries = []
    with open(HISTORY_FILE, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
                entries.append(entry)
            except json.JSONDecodeError:
                continue
    return entries


def format_entry(entry):
    """Format a single entry as: [YYYY-MM-DD HH:MM] display text"""
    ts_ms = entry.get("timestamp")
    display = entry.get("display", "")
    if ts_ms is None or not display:
        return None
    dt = datetime.fromtimestamp(ts_ms / 1000.0, tz=timezone.utc).astimezone()
    time_str = dt.strftime("%Y-%m-%d %H:%M")
    # Replace newlines with ↵ for single-line display
    display = display.replace("\n", " ↵ ")
    return f"[{time_str}] {display}"


def single_session_mode(start_ts_ms, project_path, entries):
    """Find the sessionId by matching the first entry where timestamp >= start_ts
    AND project == project_path, then output all entries for that sessionId."""
    # Find the matching sessionId
    target_session = None
    for entry in entries:
        ts = entry.get("timestamp")
        proj = entry.get("project", "")
        if ts is not None and ts >= start_ts_ms and proj == project_path:
            target_session = entry.get("sessionId")
            break

    if target_session is None:
        return

    # Output all entries for that sessionId, sorted by timestamp
    session_entries = [
        e for e in entries if e.get("sessionId") == target_session
    ]
    session_entries.sort(key=lambda e: e.get("timestamp", 0))

    for entry in session_entries:
        line = format_entry(entry)
        if line:
            print(line)


def all_sessions_mode(project_path, entries):
    """Show all entries for a project, grouped by session (contiguous),
    sorted chronologically (oldest first, newest at bottom)."""
    # Filter entries for the given project
    project_entries = [e for e in entries if e.get("project", "") == project_path]

    if not project_entries:
        return

    # Group by sessionId
    sessions = {}
    for entry in project_entries:
        sid = entry.get("sessionId", "")
        if sid not in sessions:
            sessions[sid] = []
        sessions[sid].append(entry)

    # Sort entries within each session by timestamp
    for sid in sessions:
        sessions[sid].sort(key=lambda e: e.get("timestamp", 0))

    # Sort sessions by their earliest timestamp (oldest first)
    sorted_sessions = sorted(
        sessions.items(),
        key=lambda item: min(e.get("timestamp", 0) for e in item[1]),
    )

    # Output all entries, grouped by session
    for _sid, session_entries in sorted_sessions:
        for entry in session_entries:
            line = format_entry(entry)
            if line:
                print(line)


def main():
    if len(sys.argv) < 2:
        print(
            "Usage:\n"
            "  claude-history.py <start_timestamp_ms> <project_path>\n"
            "  claude-history.py --all <project_path>",
            file=sys.stderr,
        )
        sys.exit(1)

    entries = load_entries()

    if sys.argv[1] == "--all":
        if len(sys.argv) < 3:
            print("Error: --all requires a project_path", file=sys.stderr)
            sys.exit(1)
        project_path = sys.argv[2]
        all_sessions_mode(project_path, entries)
    else:
        if len(sys.argv) < 3:
            print(
                "Error: single-session mode requires <start_timestamp_ms> <project_path>",
                file=sys.stderr,
            )
            sys.exit(1)
        try:
            start_ts_ms = int(sys.argv[1])
        except ValueError:
            print("Error: start_timestamp_ms must be an integer", file=sys.stderr)
            sys.exit(1)
        project_path = sys.argv[2]
        single_session_mode(start_ts_ms, project_path, entries)


if __name__ == "__main__":
    main()
