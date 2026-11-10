from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class LyricsVisualMotionTests(unittest.TestCase):
    def test_active_palette_changes_retarget_smoothly_and_respect_reduced_motion(self) -> None:
        lyrics = (ROOT / "modules/common/widgets/Lyrics.qml").read_text(encoding="utf-8")
        player = (ROOT / "modules/common/widgets/PlayerContent.qml").read_text(encoding="utf-8")

        self.assertIn("property color renderedAccent: root.activeColor", lyrics)
        self.assertIn("Behavior on renderedAccent {\n        enabled: root.lineMotionEnabled", lyrics)
        self.assertIn("Behavior on renderedTextColor {\n        enabled: root.lineMotionEnabled", lyrics)
        self.assertIn("ColorAnimation { duration: 180; easing.type: Easing.OutCubic }", lyrics)
        self.assertIn("karaokeMarkup(root.renderedAccent, root.renderedTextColor)", lyrics)
        self.assertIn("activeColor: root.blendedColors.colPrimary", player)

    def test_only_the_current_lyric_line_gets_a_reduced_motion_aware_breath(self) -> None:
        lyrics = (ROOT / "modules/common/widgets/Lyrics.qml").read_text(encoding="utf-8")

        self.assertIn("if (!root.lineMotionEnabled || sourceLineText.length === 0) return", lyrics)
        self.assertIn("if (lyricSlot.index === LyricsService.before) activeLinePulse.restart()", lyrics)
        self.assertIn("activeLineScale.xScale = 1.025", lyrics)
        self.assertIn('property: "xScale"; to: 1; duration: 180', lyrics)
        self.assertIn('property: "yScale"; to: 1; duration: 180', lyrics)
        self.assertIn("Accessible.name: lyricSlot.sourceLineText", lyrics)

    def test_fullscreen_accent_uses_cover_palette_and_preserves_readable_lightness(self) -> None:
        immersive = (ROOT / "modules/ii/overlay/LyricsImmersiveView.qml").read_text(encoding="utf-8")

        self.assertIn("source: coverImage", immersive)
        self.assertIn("ColorUtils.colorWithLightness(source, 0.8)", immersive)
        self.assertIn("activeColor: immersiveWindow.lyricAccent", immersive)

    def test_sync_offset_controls_are_persistent_bounded_and_exposed_in_settings(self) -> None:
        config = (ROOT / "modules/common/Config.qml").read_text(encoding="utf-8")
        service = (ROOT / "services/LyricsService.qml").read_text(encoding="utf-8")
        immersive = (ROOT / "modules/ii/overlay/LyricsImmersiveView.qml").read_text(encoding="utf-8")
        settings = (ROOT / "modules/ii/settings/DashboardSettingsCatalog.qml").read_text(encoding="utf-8")

        self.assertIn("property int lyricsSyncOffsetMs: 0", config)
        self.assertIn("Math.max(-5000, Math.min(5000", service)
        self.assertIn("function adjustLyricsSyncOffset(deltaMs)", service)
        self.assertIn("function resetLyricsSyncOffset()", service)
        self.assertGreaterEqual(service.count("root.lyricPosition()"), 4)
        self.assertIn("onLyricsSyncOffsetMsChanged: root.update()", service)
        self.assertIn("Shift lyrics later by 50 milliseconds", immersive)
        self.assertIn("Shift lyrics earlier by 50 milliseconds", immersive)
        self.assertIn("LyricsService.resetLyricsSyncOffset()", immersive)
        self.assertIn('"media:Lyrics sync offset (ms)"', settings)

    def test_fullscreen_lyrics_disclose_provider_and_timing_precision(self) -> None:
        helper = (ROOT / "scripts/lyrics/lyrics.py").read_text(encoding="utf-8")
        service = (ROOT / "services/LyricsService.qml").read_text(encoding="utf-8")
        immersive = (ROOT / "modules/ii/overlay/LyricsImmersiveView.qml").read_text(encoding="utf-8")

        self.assertIn('"timingLevel": timing_level', helper)
        self.assertIn('"source": source', helper)
        self.assertIn('root.lyricsProvider = ["lrclib", "betterlyrics"].includes(payload.source)', service)
        self.assertIn('root.lyricsTimingLevel = ["word", "cue", "line"].includes(payload.timingLevel)', service)
        self.assertIn('Translation.tr("Word-synced")', immersive)
        self.assertIn('Translation.tr("Cue-synced")', immersive)
        self.assertIn('Translation.tr("Line-synced")', immersive)


if __name__ == "__main__":
    unittest.main()
