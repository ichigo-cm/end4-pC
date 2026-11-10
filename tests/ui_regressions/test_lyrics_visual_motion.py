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


if __name__ == "__main__":
    unittest.main()
