from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MEDIA_COMPONENTS = (
    "modules/common/widgets/Player.qml",
    "modules/ii/bar/Media.qml",
    "modules/ii/background/widgets/media/MediaWidget.qml",
    "modules/ii/sidebarLeft/SidebarPlayerControl.qml",
    "modules/ii/dock/DockMedia.qml",
    "modules/ii/background/widgets/visualizer/VisualizerWidget.qml",
)


class MediaAndWeatherGuardTests(unittest.TestCase):
    def test_immersive_lyrics_buttons_do_not_override_final_qt_action_property(self) -> None:
        source = (ROOT / "modules/ii/overlay/LyricsImmersiveView.qml").read_text(encoding="utf-8")
        self.assertNotIn("property var action", source)
        self.assertIn("property var callback", source)
        self.assertIn("downAction: () => { if (callback) callback(); }", source)
        self.assertEqual(source.count("callback: () =>"), 4)

    def test_karaoke_uses_weighted_cue_and_line_pacing(self) -> None:
        source = (ROOT / "services/LyricsService.qml").read_text(encoding="utf-8")
        self.assertIn("function weightedRevealCount(text, progress, weights)", source)
        self.assertIn("root.weightedRevealCount(cueText, cueProgress, cue.weights)", source)
        self.assertIn("root.weightedRevealCount(text, progress, lineWeights)", source)
        self.assertIn("karaokeWeights: root.normalizedTimingWeights", source)
        self.assertIn("interval: root.karaokeMotion ? 33 : 100", source)

    def test_lyrics_fetch_receives_mpris_album_metadata(self) -> None:
        source = (ROOT / "services/LyricsService.qml").read_text(encoding="utf-8")
        self.assertIn('const album = root.activePlayer?.trackAlbum ?? ""', source)
        self.assertIn("String(Math.floor(duration)), album", source)
        self.assertIn("function onTrackAlbumChanged() { restartDebounce.restart() }", source)

    def test_all_cover_downloaders_ignore_stale_results_and_retry_current_art(self) -> None:
        for relative_path in MEDIA_COMPONENTS:
            with self.subTest(component=relative_path):
                source = (ROOT / relative_path).read_text(encoding="utf-8")
                self.assertIn("property int requestVersion: 0", source)
                self.assertRegex(source, r"requestVersion !== root\.artRequestVersion")
                self.assertIn("targetFile !== root.artUrl", source)
                self.assertIn("artFilePath !== root.artFilePath", source)
                self.assertIn("Qt.callLater(() => root.", source)

    def test_weather_api_error_payload_marks_cache_stale(self) -> None:
        source = (ROOT / "services/Weather.qml").read_text(encoding="utf-8")
        error_branch = re.search(
            r"if \(parsedData\.cod !== undefined && Number\(parsedData\.cod\) !== 200\) \{(?P<body>.*?)\n\s*\}",
            source,
            re.DOTALL,
        )
        self.assertIsNotNone(error_branch)
        self.assertIn("root.offline = true", error_branch.group("body"))
        key_error_branch = re.search(
            r'if \(!apiKey \|\| apiKey === ""\) \{(?P<body>.*?)\n\s*\}',
            source,
            re.DOTALL,
        )
        self.assertIsNotNone(key_error_branch)
        self.assertIn("root.offline = true", key_error_branch.group("body"))


if __name__ == "__main__":
    unittest.main()
