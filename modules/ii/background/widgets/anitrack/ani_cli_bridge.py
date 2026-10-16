#!/usr/bin/env python3
"""Read ani-cli's native history and launch it without shell interpolation."""
from __future__ import annotations

import argparse
import json
import os
import shlex
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any


def history_path(environ: dict[str, str] | None = None) -> Path:
    env = os.environ if environ is None else environ
    custom_dir = env.get("ANI_CLI_HIST_DIR")
    if custom_dir:
        return Path(custom_dir).expanduser() / "ani-hsts"
    state_home = env.get("XDG_STATE_HOME")
    base = Path(state_home).expanduser() if state_home else Path(env.get("HOME", str(Path.home()))).expanduser() / ".local" / "state"
    return base / "ani-cli" / "ani-hsts"


def parse_history_line(line: str) -> dict[str, str] | None:
    line = line.rstrip("\r\n")
    if not line.strip():
        return None
    fields = line.split("\t", 2)
    if len(fields) != 3:
        fields = line.split(None, 2)
    if len(fields) != 3:
        return None
    episode, anime_id, title = (field.strip() for field in fields)
    if not episode or not anime_id or not title:
        return None
    if any(ord(character) < 32 for character in episode + anime_id + title):
        return None
    return {"episode": episode, "anime_id": anime_id, "title": title}


def read_history(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {"ok": True, "historyFound": False, "entries": [], "malformed": 0}
    try:
        contents = path.read_text(encoding="utf-8")
    except (OSError, UnicodeError) as error:
        return {"ok": False, "error": f"Could not read ani-cli history: {error}"}

    entries_by_id: dict[str, dict[str, str]] = {}
    malformed = 0
    for line in contents.splitlines():
        entry = parse_history_line(line)
        if entry is None:
            if line.strip():
                malformed += 1
            continue
        # Preserve file order, but use the final saved value for duplicate IDs.
        entries_by_id[entry["anime_id"]] = entry
    return {
        "ok": True,
        "historyFound": True,
        "entries": list(entries_by_id.values()),
        "malformed": malformed,
    }


def executable_path(name: str) -> str | None:
    expanded = os.path.expanduser(name)
    if os.path.sep in expanded:
        candidate = Path(expanded)
        return str(candidate) if candidate.is_file() and os.access(candidate, os.X_OK) else None
    return shutil.which(expanded)


def terminal_argv(terminal_setting: str, ani_cli: str, title: str | None) -> list[str]:
    terminal = shlex.split(terminal_setting, posix=True)
    if not terminal:
        raise ValueError("No terminal command is configured.")
    resolved_terminal = executable_path(terminal[0])
    if not resolved_terminal:
        raise FileNotFoundError(f"Configured terminal was not found: {terminal[0]}")
    terminal[0] = resolved_terminal
    terminal_name = Path(resolved_terminal).name.lower()
    if terminal_name == "wezterm":
        command = ["start", "--", ani_cli]
    elif terminal_name == "gnome-terminal":
        command = ["--", ani_cli]
    else:
        command = ["-e", ani_cli]
    if title is None:
        command.append("--continue")
    else:
        clean_title = " ".join(title.replace("\x00", " ").split())
        if not clean_title:
            raise ValueError("Choose an anime title before opening ani-cli.")
        if clean_title.startswith("-"):
            raise ValueError("This title begins with an ani-cli option prefix and cannot be launched safely.")
        if len(clean_title) > 240:
            raise ValueError("The selected title is too long to pass to ani-cli.")
        command.append(clean_title)
    return [*terminal, *command]


def launch(terminal_setting: str, title: str | None) -> dict[str, Any]:
    ani_cli = executable_path("ani-cli")
    if not ani_cli:
        return {"ok": False, "error": "ani-cli was not found in Quickshell's PATH."}
    try:
        argv = terminal_argv(terminal_setting, ani_cli, title)
        process = subprocess.Popen(
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            close_fds=True,
            start_new_session=True,
        )
        time.sleep(0.15)
        return_code = process.poll()
        if return_code is not None and return_code != 0:
            return {"ok": False, "error": f"The configured terminal exited with status {return_code}."}
    except (OSError, ValueError) as error:
        return {"ok": False, "error": str(error)}
    return {
        "ok": True,
        "message": "Terminal opened. Choose the episode in ani-cli to begin playback."
        if title is not None
        else "ani-cli history opened in the configured terminal.",
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="action", required=True)
    subparsers.add_parser("read-history", help="Read ani-cli's native history file")
    launch_parser = subparsers.add_parser("launch", help="Launch ani-cli in the configured terminal")
    launch_parser.add_argument("--terminal", required=True)
    mode = launch_parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--title")
    mode.add_argument("--continue", dest="continue_history", action="store_true")
    args = parser.parse_args(argv)

    if args.action == "read-history":
        result = read_history(history_path())
    else:
        result = launch(args.terminal, None if args.continue_history else args.title)
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
