from __future__ import annotations

import importlib.util
import io
import json
import subprocess
import unittest
from pathlib import Path
from types import SimpleNamespace
import urllib.parse
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

    def test_karaoke_weights_hold_vowels_and_punctuation_longer(self) -> None:
        weights = lyrics_parser._karaoke_character_weights("sing!")
        self.assertEqual(len(weights), len("sing!"))
        self.assertGreater(weights[1], weights[0])
        self.assertGreater(weights[-1], weights[-2])

    def test_enrichment_attaches_weights_to_main_full_and_timed_cue_text(self) -> None:
        lines = lyrics_parser._enrich_lines([{
            "time": 1.0,
            "text": "Sing (oh!) now",
            "cues": [
                {"time": 1.0, "text": "Sing (oh!)"},
                {"time": 2.0, "text": "now"},
            ],
        }])
        line = lines[0]
        self.assertEqual(line["text"], "Sing now")
        self.assertEqual(len(line["karaokeWeights"]), len(line["text"]))
        self.assertEqual(len(line["fullKaraokeWeights"]), len(line["fullText"]))
        self.assertEqual(len(line["cues"][0]["weights"]), len(line["cues"][0]["text"]))
        self.assertEqual(len(line["fullCues"][0]["weights"]), len(line["fullCues"][0]["text"]))

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

    def test_better_lyrics_namespaced_x_bg_role_is_separated_from_lead(self) -> None:
        source = '''
        <tt xmlns:ttm="http://www.w3.org/ns/ttml#metadata">
          <body><p begin="00:00:01.000">
            <span begin="00:00:01.000" end="00:00:01.500">Lead </span>
            <span ttm:role="x-bg"><span begin="00:00:01.500" end="00:00:02.000">echo</span></span>
          </p></body>
        </tt>
        '''
        lines = lyrics_parser._parse_ttml(source)
        self.assertEqual(lines[0]["text"], "Lead")
        self.assertEqual(lines[0]["fullText"], "Lead echo")
        self.assertEqual(lines[0]["vocalLayers"][0]["type"], "background")
        self.assertEqual(lines[0]["cues"], [{"time": 1.0, "end": 1.5, "text": "Lead"}])
        self.assertEqual(lines[0]["fullCues"][-1], {"time": 1.5, "end": 2.0, "text": "echo"})

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

    def test_lyricsfile_word_timing_becomes_timed_cues(self) -> None:
        source = '''
version: "1.0"
metadata:
  title: "Still Alive"
lines: # word-synced lines
  - text: "This was a triumph." # preserve explicit line text
    start_ms: 290
    end_ms: 3840
    words: # per-word time ranges
      - text: "This "
        start_ms: 290
        end_ms: 536
      - text: "was "
        start_ms: 536
        end_ms: 784
      - text: "a "
        start_ms: 784
        end_ms: 923
      - text: triumph.
        start_ms: 923
        end_ms: 3840
'''
        lines = lyrics_parser._parse_lyricsfile(source)
        self.assertEqual(len(lines), 1)
        self.assertEqual(lines[0]["time"], 0.29)
        self.assertEqual(lines[0]["text"], "This was a triumph.")
        self.assertEqual(lines[0]["cues"][0], {"time": 0.29, "end": 0.536, "text": "This "})
        self.assertEqual(lines[0]["cues"][-1], {"time": 0.923, "end": 3.84, "text": "triumph."})

    def test_lyricsfile_parser_accepts_indentationless_yaml_sequence(self) -> None:
        source = '''
version: "1.0"
lines:
- text: "A line"
  start_ms: 1000
  end_ms: 2000
  words:
  - text: "A "
    start_ms: 1000
    end_ms: 1300
  - text: line
    start_ms: 1300
    end_ms: 2000
'''
        lines = lyrics_parser._parse_lyricsfile(source)
        self.assertEqual(lines[0]["text"], "A line")
        self.assertEqual([cue["time"] for cue in lines[0]["cues"]], [1.0, 1.3])

    def test_lrclib_word_sync_request_identifies_client_and_matches_album(self) -> None:
        record = {
            "trackName": "Still Alive",
            "artistName": "Aperture Science",
            "hasWordSync": True,
            "lyricsfile": '''
version: "1.0"
lines:
  - text: "Still alive"
    start_ms: 1000
    end_ms: 2500
    words:
      - text: "Still "
        start_ms: 1000
        end_ms: 1700
      - text: alive
        start_ms: 1700
        end_ms: 2500
''',
        }
        body = io.BytesIO(json.dumps(record).encode("utf-8"))
        with patch.object(lyrics_parser.urllib.request, "urlopen", return_value=body) as open_url:
            word_synced, line_synced = lyrics_parser.fetch_lrclib_candidates(
                "Still Alive", "Aperture Science", 176, "Portal"
            )
        request = open_url.call_args.args[0]
        self.assertIn("album_name=Portal", request.full_url)
        self.assertEqual(request.get_header("User-agent"), "end4-pC lyrics helper/1.0 (https://github.com/ichigo-cm/end4-pC)")
        self.assertTrue(word_synced)
        self.assertEqual(line_synced, [])

    def test_better_lyrics_query_includes_album_and_duration(self) -> None:
        ttml = "<tt><body>" + "".join(
            f'<p begin="{index}s"><span begin="{index}s" end="{index + 0.5}s">line {index}</span></p>'
            for index in range(3)
        ) + "</body></tt>"
        body = io.BytesIO(json.dumps({"ttml": ttml}).encode("utf-8"))
        with patch.object(lyrics_parser.urllib.request, "urlopen", return_value=body) as open_url:
            lines = lyrics_parser.fetch_boidu("Song", "Artist", 180, "Album")
        request = open_url.call_args.args[0]
        params = urllib.parse.parse_qs(urllib.parse.urlsplit(request.full_url).query)
        self.assertEqual(params["al"], ["Album"])
        self.assertEqual(params["d"], ["180"])
        self.assertEqual(len(lines), 3)

    def test_word_only_lrclib_record_is_a_match_without_synced_lrc(self) -> None:
        record = {
            "trackName": "Still Alive",
            "artistName": "Aperture Science",
            "hasWordSync": True,
            "lyricsfile": "version: '1.0'\nlines: []",
        }
        self.assertTrue(lyrics_parser._is_match(record, "Still Alive", "Aperture Science"))

    def test_source_selection_prefers_lrclib_word_sync_then_ttml_then_lrc(self) -> None:
        word_sync = [{"time": 1.0, "text": "word", "cues": [{"time": 1.0, "end": 2.0, "text": "word"}]}]
        line_sync = [{"time": 1.0, "text": "line"}]
        ttml = [{"time": 1.0, "text": "timed", "cues": [{"time": 1.0, "end": 2.0, "text": "timed"}]}]

        with patch.object(lyrics_parser, "fetch_lrclib_candidates", return_value=(word_sync, line_sync)), \
                patch.object(lyrics_parser, "fetch_boidu") as fetch_ttml:
            self.assertEqual(lyrics_parser.fetch_best_lyrics("t", "a", 3), word_sync)
            fetch_ttml.assert_not_called()

        with patch.object(lyrics_parser, "fetch_lrclib_candidates", return_value=([], line_sync)), \
                patch.object(lyrics_parser, "fetch_boidu", return_value=ttml):
            self.assertEqual(lyrics_parser.fetch_best_lyrics("t", "a", 3), ttml)

        with patch.object(lyrics_parser, "fetch_lrclib_candidates", return_value=([], line_sync)), \
                patch.object(lyrics_parser, "fetch_boidu", return_value=[{"time": 1.0, "text": "untimed"}]):
            self.assertEqual(lyrics_parser.fetch_best_lyrics("t", "a", 3), line_sync)


if __name__ == "__main__":
    unittest.main()
