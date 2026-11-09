from __future__ import annotations

import importlib.util
import subprocess
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[2] / "scripts/lyrics/lyrics.py"
SPEC = importlib.util.spec_from_file_location("lyrics_parser", SCRIPT)
lyrics_parser = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(lyrics_parser)


class LyricsTimingTests(unittest.TestCase):
    def test_plain_lrc_keeps_line_timestamps_without_fabricating_word_cues(self) -> None:
        lines = lyrics_parser._parse_lrc("[00:01.25]Hello there\n[00:03.00]Next line")
        self.assertEqual([line["time"] for line in lines], [1.25, 3.0])
        self.assertEqual([line["text"] for line in lines], ["Hello there", "Next line"])
        self.assertNotIn("cues", lines[0])

    def test_enhanced_lrc_preserves_syllable_timing_and_plain_text(self) -> None:
        lines = lyrics_parser._parse_lrc("[00:10.00]<00:10.00>Hel<00:10.24>lo <00:10.52>there!")
        self.assertEqual(len(lines), 1)
        self.assertEqual(lines[0]["text"], "Hello there!")
        self.assertEqual(
            lines[0]["cues"],
            [
                {"time": 10.0, "text": "Hel"},
                {"time": 10.24, "text": "lo"},
                {"time": 10.52, "text": "there!"},
            ],
        )

    def test_repeated_lrc_line_timestamps_shift_inline_cues(self) -> None:
        lines = lyrics_parser._parse_lrc("[00:10.00][00:12.00]<00:10.00>Hello")
        self.assertEqual([line["time"] for line in lines], [10.0, 12.0])
        self.assertEqual([line["cues"][0]["time"] for line in lines], [10.0, 12.0])

    def test_ttml_timed_spans_are_retained_as_word_cues(self) -> None:
        source = """
        <tt xmlns="http://www.w3.org/ns/ttml">
          <body><div>
            <p begin="00:00:10.000" end="00:00:12.000">
              <span begin="0.1s" end="0.35s">Hello </span>
              <span begin="0.5s" end="0.9s">world!</span>
            </p>
          </div></body>
        </tt>
        """
        lines = lyrics_parser._parse_ttml(source)
        self.assertEqual(lines[0]["text"], "Hello world!")
        self.assertEqual(lines[0]["time"], 10.0)
        self.assertEqual(
            lines[0]["cues"],
            [
                {"time": 10.1, "end": 10.35, "text": "Hello"},
                {"time": 10.5, "end": 10.9, "text": "world!"},
            ],
        )

    def test_ttml_clock_cue_before_parent_is_interpreted_as_relative_offset(self) -> None:
        source = "<tt><body><p begin=\"00:00:05.000\"><span begin=\"00:00:00.400\">word</span></p></body></tt>"
        lines = lyrics_parser._parse_ttml(source)
        self.assertEqual(lines[0]["cues"][0]["time"], 5.4)

    def test_parenthetical_vocals_are_split_without_losing_primary_word_timing(self) -> None:
        lines = lyrics_parser._enrich_lines([{
            "time": 2.0,
            "text": "Take it (oh, oh) home",
            "cues": [
                {"time": 2.0, "text": "Take it (oh, oh)"},
                {"time": 2.5, "text": "home"},
            ],
        }])
        self.assertEqual(lines[0]["text"], "Take it home")
        self.assertEqual(lines[0]["fullText"], "Take it (oh, oh) home")
        self.assertEqual([cue["text"] for cue in lines[0]["cues"]], ["Take it", "home"])
        self.assertEqual(lines[0]["fullCues"][0]["text"], "Take it (oh, oh)")
        self.assertEqual(lines[0]["vocalLayers"], [
            {"type": "background", "text": "oh, oh", "time": 2.0},
        ])

    def test_side_vocal_prefix_is_exposed_as_a_separate_layer(self) -> None:
        lines = lyrics_parser._enrich_lines([{"time": 1.0, "text": "Hello (side: yeah)"}])
        self.assertEqual(lines[0]["text"], "Hello")
        self.assertEqual(lines[0]["vocalLayers"][0]["type"], "side")
        self.assertEqual(lines[0]["vocalLayers"][0]["text"], "yeah")

    def test_ttml_background_role_is_extracted_as_a_timed_vocal_layer(self) -> None:
        source = """
        <tt><body><p begin="00:00:01.000">Lead
          <span role="background" begin="0.2s" end="0.5s">echo</span>
        </p></body></tt>
        """
        lines = lyrics_parser._parse_ttml(source)
        self.assertEqual(lines[0]["text"], "Lead")
        self.assertEqual(lines[0]["fullText"], "Lead echo")
        self.assertEqual(lines[0]["vocalLayers"], [{
            "type": "background", "text": "echo", "time": 1.2, "end": 1.5,
        }])
        self.assertEqual(lines[0]["fullCues"], [{
            "time": 1.2, "end": 1.5, "text": "echo",
        }])

    def test_dependency_free_romanization_handles_kana_and_hangul(self) -> None:
        self.assertEqual(lyrics_parser._romanize_kana("かな"), "kana")
        self.assertEqual(lyrics_parser._romanize_hangul("안녕"), "annyeong")

    def test_dictionary_dependent_han_is_not_falsely_claimed_without_icu(self) -> None:
        with patch.object(lyrics_parser.shutil, "which", return_value=None):
            self.assertEqual(lyrics_parser._romanize_text("你好"), "")

    def test_track_romanization_batches_all_line_variants_into_one_icu_call(self) -> None:
        result = SimpleNamespace(returncode=0, stdout="kana\nkana\n")
        with patch.object(lyrics_parser.shutil, "which", return_value="/usr/bin/uconv"), \
                patch.object(lyrics_parser.subprocess, "run", return_value=result) as run:
            lines = lyrics_parser._enrich_lines([{"time": 0.0, "text": "かな"}])
        self.assertEqual(lines[0]["romanizedText"], "kana")
        self.assertEqual(lines[0]["romanizedFullText"], "kana")
        run.assert_called_once()


if __name__ == "__main__":
    unittest.main()
