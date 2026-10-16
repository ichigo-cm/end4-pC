#!/usr/bin/env python3
"""Read AniTrack's local watch history without modifying its SQLite database."""

from __future__ import annotations

import json
import os
import sqlite3
import sys
from pathlib import Path


def database_path() -> Path:
    xdg_data_home = os.environ.get("XDG_DATA_HOME", "")
    if xdg_data_home and Path(xdg_data_home).is_absolute():
        data_home = Path(xdg_data_home)
    else:
        data_home = Path.home() / ".local" / "share"
    return data_home / "anitrack" / "anitrack.db"


def emit(payload: dict[str, object], exit_code: int = 0) -> None:
    print(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    if exit_code:
        raise SystemExit(exit_code)


def main() -> None:
    path = database_path()
    if not path.is_file():
        emit({"ok": True, "databaseFound": False, "entries": []})
        return

    # SQLite URI mode=ro prevents AniTrack's history from being changed by the widget.
    connection_uri = path.resolve().as_uri() + "?mode=ro"
    try:
        with sqlite3.connect(connection_uri, uri=True, timeout=2.0) as connection:
            connection.row_factory = sqlite3.Row
            connection.execute("PRAGMA query_only = ON")
            tables = {
                row[0]
                for row in connection.execute(
                    "SELECT name FROM sqlite_master WHERE type = 'table'"
                )
            }
            if "seen_progress" not in tables:
                emit(
                    {
                        "ok": False,
                        "databaseFound": True,
                        "entries": [],
                        "error": "AniTrack database does not contain watch-history data.",
                    },
                    1,
                )

            columns = {
                row[1]
                for row in connection.execute("PRAGMA table_info(seen_progress)")
            }
            required = {"title", "last_episode", "last_seen_at"}
            if not required.issubset(columns):
                emit(
                    {
                        "ok": False,
                        "databaseFound": True,
                        "entries": [],
                        "error": "AniTrack watch-history schema is not recognized.",
                    },
                    1,
                )

            total_expression = (
                "total_episodes" if "total_episodes" in columns else "NULL AS total_episodes"
            )
            rows = connection.execute(
                "SELECT title, last_episode, last_seen_at, "
                + total_expression
                + " FROM seen_progress ORDER BY last_seen_at DESC"
            ).fetchall()

            entries = [
                {
                    "title": row["title"] or "Untitled anime",
                    "last_episode": row["last_episode"],
                    "last_seen_at": row["last_seen_at"],
                    "total_episodes": row["total_episodes"],
                }
                for row in rows
            ]
            emit({"ok": True, "databaseFound": True, "entries": entries})
    except (sqlite3.Error, OSError) as error:
        emit(
            {
                "ok": False,
                "databaseFound": True,
                "entries": [],
                "error": f"Could not read AniTrack's local database: {error}",
            },
            1,
        )


if __name__ == "__main__":
    main()
