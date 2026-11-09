from __future__ import annotations

import re
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TIMER_SERVICE = ROOT / "services" / "TimerService.qml"
PERSISTENT = ROOT / "modules" / "common" / "Persistent.qml"


class StopwatchPersistenceTests(unittest.TestCase):
    def test_runtime_and_persisted_stopwatch_ticks_use_real_fields(self) -> None:
        service = TIMER_SERVICE.read_text(encoding="utf-8")
        persistent = PERSISTENT.read_text(encoding="utf-8")
        self.assertRegex(service, r"property real stopwatchTime\s*:\s*0")
        self.assertRegex(service, r"property real stopwatchStart\s*:\s*Persistent\.states\.timer\.stopwatch\.start")
        match = re.search(
            r"property JsonObject stopwatch: JsonObject \{(?P<body>.*?)\n\s*\}\n\s*property JsonObject countdown",
            persistent,
            re.DOTALL,
        )
        self.assertIsNotNone(match)
        self.assertRegex(match.group("body"), r"property real start\s*:\s*0")
        self.assertRegex(match.group("body"), r"property real elapsed\s*:\s*0")

    def test_epoch_ticks_fit_exactly_in_qml_double_precision(self) -> None:
        current_ticks = int(time.time() * 1000) // 10
        self.assertLess(current_ticks, 2**53)
        service = TIMER_SERVICE.read_text(encoding="utf-8")
        self.assertIn("Math.floor(Date.now() / 10)", service)
        self.assertIn("Number.isFinite(savedStart)", service)
        self.assertIn("savedStart < currentTicks / 2", service)
        self.assertIn("Number(Persistent.states.timer.stopwatch.elapsed)", service)


if __name__ == "__main__":
    unittest.main()
