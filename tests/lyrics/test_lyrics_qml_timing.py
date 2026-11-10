from __future__ import annotations

import json
import re
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
QML_SERVICE = ROOT / "services/LyricsService.qml"
NODE = shutil.which("node")


def _extract_qml_function(source: str, name: str) -> str:
    match = re.search(rf"\bfunction\s+{re.escape(name)}\s*\(", source)
    if match is None:
        raise AssertionError(f"Could not find QML JavaScript function {name}")
    opening = source.find("{", match.end())
    if opening < 0:
        raise AssertionError(f"Could not find body for QML JavaScript function {name}")

    depth = 0
    quote = ""
    escaped = False
    for index in range(opening, len(source)):
        char = source[index]
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
            continue
        if char in ("'", '"', "`"):
            quote = char
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[match.start():index + 1]
    raise AssertionError(f"Unterminated QML JavaScript function {name}")


@unittest.skipUnless(NODE, "Node.js is unavailable; skip executing QML JavaScript helpers")
class LyricsQmlTimingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        source = QML_SERVICE.read_text(encoding="utf-8")
        cls.functions = "\n".join(
            _extract_qml_function(source, name)
            for name in (
                "normalizedTimingWeights",
                "weightedRevealCount",
                "revealCountAt",
                "lyricPosition",
                "indexAt",
                "setLyricsSyncOffset",
                "adjustLyricsSyncOffset",
                "resetLyricsSyncOffset",
            )
        )

    def reveal_counts(self, line: dict, positions: list[float]) -> list[int]:
        fallback_end = line.get("fallbackEnd", 8)
        show_vocal_layers = json.dumps(line.get("showVocalLayers", True))
        script = f"""
{self.functions}
const Config = {{ options: {{ media: {{ showVocalLayers: {show_vocal_layers} }} }} }};
const root = {{ lyricsLines: [{json.dumps(line)}], lineEndPosition: () => {fallback_end} }};
root.normalizedTimingWeights = normalizedTimingWeights;
root.weightedRevealCount = weightedRevealCount;
const counts = {json.dumps(positions)}.map(position => revealCountAt(0, position));
console.log(JSON.stringify(counts));
"""
        result = subprocess.run(
            [NODE, "-e", script], check=True, capture_output=True, text=True, timeout=10
        )
        return json.loads(result.stdout)

    def offset_indexes(self) -> list[int]:
        script = f"""
{self.functions}
const root = {{
  currentPosition: () => 10.05,
  leadSeconds: 0.05,
  lyricsOffsetSeconds: 0,
  lyricsLines: [{{ time: 0 }}, {{ time: 10.15 }}]
}};
root.lyricPosition = lyricPosition;
root.indexAt = indexAt;
const offsets = [-100, 0, 100];
console.log(JSON.stringify(offsets.map(offset => {{
  root.lyricsOffsetSeconds = offset / 1000;
  return root.indexAt(root.lyricPosition());
}})));
"""
        result = subprocess.run(
            [NODE, "-e", script], check=True, capture_output=True, text=True, timeout=10
        )
        return json.loads(result.stdout)

    def offset_adjustments(self) -> list[int]:
        script = f"""
{self.functions}
const Config = {{ options: {{ media: {{ lyricsSyncOffsetMs: 4980 }} }} }};
const root = {{
  get lyricsSyncOffsetMs() {{ return Config.options.media.lyricsSyncOffsetMs; }},
  setLyricsSyncOffset,
  adjustLyricsSyncOffset,
  resetLyricsSyncOffset
}};
const result = [
  root.adjustLyricsSyncOffset(50),
  root.adjustLyricsSyncOffset(50),
  root.adjustLyricsSyncOffset(-50),
  root.resetLyricsSyncOffset()
];
console.log(JSON.stringify(result));
"""
        result = subprocess.run(
            [NODE, "-e", script], check=True, capture_output=True, text=True, timeout=10
        )
        return json.loads(result.stdout)

    def test_line_only_fallback_uses_weighted_speech_units(self) -> None:
        line = {
            "time": 0,
            "text": "sing!",
            "fullText": "sing!",
            "karaokeWeights": [0.52, 1.8, 0.78, 0.52, 2.2],
            "fullKaraokeWeights": [0.52, 1.8, 0.78, 0.52, 2.2],
            "fallbackEnd": 4,
            "cues": [],
        }
        self.assertEqual(self.reveal_counts(line, [0, 2.2, 4]), [0, 3, 5])

    def test_timed_cues_keep_fast_and_slow_intervals_distinct(self) -> None:
        weights = [0.78, 1.8, 0.78, 0.52]
        line = {
            "time": 0,
            "text": "word word",
            "fullText": "word word",
            "karaokeWeights": [0.78, 1.8, 0.78, 0.52, 0.28, 0.78, 1.8, 0.78, 0.52],
            "fullKaraokeWeights": [0.78, 1.8, 0.78, 0.52, 0.28, 0.78, 1.8, 0.78, 0.52],
            "cues": [
                {"time": 0, "end": 1, "text": "word", "weights": weights},
                {"time": 2, "end": 6, "text": "word", "weights": weights},
            ],
        }
        self.assertEqual(self.reveal_counts(line, [0.5, 2.5]), [1, 5])

    def test_full_vocal_mode_uses_full_text_cues(self) -> None:
        line = {
            "time": 0,
            "text": "lead",
            "fullText": "lead echo",
            "karaokeWeights": [0.78, 1.8, 1.8, 0.52],
            "fullKaraokeWeights": [0.78, 1.8, 1.8, 0.52, 0.28, 1.8, 0.52, 0.52, 1.8],
            "showVocalLayers": False,
            "cues": [{"time": 0, "end": 1, "text": "lead", "weights": [0.78, 1.8, 1.8, 0.52]}],
            "fullCues": [
                {"time": 0, "end": 1, "text": "lead", "weights": [0.78, 1.8, 1.8, 0.52]},
                {"time": 1, "end": 3, "text": "echo", "weights": [1.8, 0.52, 0.52, 1.8]},
            ],
        }
        self.assertEqual(self.reveal_counts(line, [2]), [7])

    def test_uncovered_trailing_text_progresses_during_last_cue_window(self) -> None:
        line = {
            "time": 0,
            "text": "lead tail",
            "fullText": "lead tail",
            "karaokeWeights": [0.78, 1.8, 1.8, 0.52, 0.28, 0.52, 1.8, 1.8, 0.78],
            "fullKaraokeWeights": [0.78, 1.8, 1.8, 0.52, 0.28, 0.52, 1.8, 1.8, 0.78],
            "cues": [{"time": 0, "text": "lead", "weights": [0.78, 1.8, 1.8, 0.52]}],
        }
        revealed = self.reveal_counts(line, [4])[0]
        self.assertGreater(revealed, len("lead"))
        self.assertLess(revealed, len(line["text"]))

    def test_sync_offset_moves_line_selection_in_the_expected_direction(self) -> None:
        self.assertEqual(self.offset_indexes(), [0, 0, 1])

    def test_sync_offset_is_clamped_and_resettable(self) -> None:
        self.assertEqual(self.offset_adjustments(), [5000, 5000, 4950, 0])


if __name__ == "__main__":
    unittest.main()
