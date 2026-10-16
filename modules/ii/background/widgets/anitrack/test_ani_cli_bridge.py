from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

MODULE_PATH = Path(__file__).with_name("ani_cli_bridge.py")
SPEC = importlib.util.spec_from_file_location("ani_cli_bridge", MODULE_PATH)
bridge = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(bridge)


class AniCliBridgeTests(unittest.TestCase):
    def test_reads_xdg_state_history_path(self) -> None:
        result = bridge.history_path({"XDG_STATE_HOME": "/tmp/state"})
        self.assertEqual(result, Path("/tmp/state/ani-cli/ani-hsts"))

    def test_custom_history_directory_takes_precedence(self) -> None:
        result = bridge.history_path({
            "ANI_CLI_HIST_DIR": "/tmp/custom",
            "XDG_STATE_HOME": "/tmp/state",
        })
        self.assertEqual(result, Path("/tmp/custom/ani-hsts"))

    def test_parses_native_tsv_and_legacy_whitespace(self) -> None:
        self.assertEqual(
            bridge.parse_history_line("12\tshow-1\tA title with spaces\n"),
            {"episode": "12", "anime_id": "show-1", "title": "A title with spaces"},
        )
        self.assertEqual(
            bridge.parse_history_line("7 show-2 Another title with spaces"),
            {"episode": "7", "anime_id": "show-2", "title": "Another title with spaces"},
        )

    def test_ignores_malformed_lines_and_keeps_last_saved_duplicate(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ani-hsts"
            path.write_text(
                "2\tshow-1\tFirst title\ninvalid\n9\tshow-1\tUpdated title\n",
                encoding="utf-8",
            )
            result = bridge.read_history(path)
        self.assertTrue(result["historyFound"])
        self.assertEqual(result["malformed"], 1)
        self.assertEqual(result["entries"], [
            {"episode": "9", "anime_id": "show-1", "title": "Updated title"}
        ])

    def test_history_read_is_read_only(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "ani-hsts"
            original = b"12\tshow-1\tA title\n"
            path.write_bytes(original)
            bridge.read_history(path)
            self.assertEqual(path.read_bytes(), original)

    def test_missing_history_is_not_an_error(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = bridge.read_history(Path(directory) / "missing")
        self.assertTrue(result["ok"])
        self.assertFalse(result["historyFound"])
        self.assertEqual(result["entries"], [])

    def test_selected_title_is_one_argv_value_and_never_shell_expanded(self) -> None:
        with (
            patch.object(bridge, "executable_path", side_effect=["/usr/bin/ani-cli", "/usr/bin/kitty"]),
            patch.object(bridge.subprocess, "Popen") as popen,
        ):
            popen.return_value.poll.return_value = None
            launched = bridge.launch("kitty -1", "Anime; touch /tmp/not-created")
        self.assertTrue(launched["ok"])
        argv = popen.call_args.args[0]
        self.assertEqual(argv, [
            "/usr/bin/kitty", "-1", "-e", "/usr/bin/ani-cli", "Anime; touch /tmp/not-created"
        ])

    def test_continue_launch_uses_native_continue_flag(self) -> None:
        with patch.object(bridge, "executable_path", return_value="/usr/bin/kitty"):
            argv = bridge.terminal_argv("kitty -1", "/usr/bin/ani-cli", None)
        self.assertEqual(argv[-1], "--continue")

    def test_option_looking_title_is_rejected(self) -> None:
        with patch.object(bridge, "executable_path", return_value="/usr/bin/kitty"):
            with self.assertRaisesRegex(ValueError, "cannot be launched safely"):
                bridge.terminal_argv("kitty -1", "/usr/bin/ani-cli", "--delete")

    def test_missing_terminal_is_reported(self) -> None:
        with patch.object(bridge, "executable_path", return_value=None):
            with self.assertRaises(FileNotFoundError):
                bridge.terminal_argv("missing-terminal", "/usr/bin/ani-cli", "Anime")

    def test_missing_ani_cli_is_reported_without_spawning_terminal(self) -> None:
        with patch.object(bridge, "executable_path", return_value=None), \
                patch.object(bridge.subprocess, "Popen") as popen:
            result = bridge.launch("kitty -1", "Anime")
        self.assertFalse(result["ok"])
        self.assertIn("ani-cli was not found", result["error"])
        popen.assert_not_called()


if __name__ == "__main__":
    unittest.main()
