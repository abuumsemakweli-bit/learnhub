from datetime import datetime, timezone
import unittest
from unittest.mock import patch

import signal_engine
from signal_engine import (
    Candle,
    MarketQuote,
    _score,
    analyze_market,
)


def candles(count: int, *, step: float = 0.001) -> list[Candle]:
    now = 1_792_766_400
    return [
        Candle(
            time=now + index * 300,
            open=1.1 + index * step,
            high=1.102 + index * step,
            low=1.099 + index * step,
            close=1.101 + index * step,
        )
        for index in range(count)
    ]


class SignalEngineTests(unittest.TestCase):
    def setUp(self) -> None:
        self.now = datetime(2026, 10, 23, 17, 12, tzinfo=timezone.utc)
        self.quote = MarketQuote(
            bid=1.12,
            ask=1.12008,
            time=int(self.now.timestamp()),
            digits=5,
            point=0.00001,
        )
        self.h4 = candles(100, step=0)
        self.h1 = candles(100, step=0)
        self.m15 = [
            Candle(
                time=candle.time + 100_000,
                open=candle.open,
                high=candle.high,
                low=candle.low,
                close=candle.close,
            )
            for candle in candles(120, step=0)
        ]

    def test_market_mechanism_score_weights_total_thirteen(self) -> None:
        criteria = {
            "h4_trend_alignment": True,
            "h1_structure_alignment": True,
            "liquidity_identified": True,
            "liquidity_sweep": True,
            "structure_shift": True,
            "displacement": True,
            "entry_zone": True,
            "risk_reward": True,
        }
        self.assertEqual(_score(criteria), 13)

    def test_strong_signal_scores_market_mechanism_confluences(self) -> None:
        with (
            patch.object(signal_engine, "_structure_bias", return_value="BUY"),
            patch.object(
                signal_engine, "_liquidity_sweep", return_value=("BUY", 25, 1.0)
            ),
            patch.object(
                signal_engine, "_structure_shift_index", return_value=30
            ),
            patch.object(
                signal_engine, "_mitigated_order_block", return_value=(True, None)
            ),
            patch.object(signal_engine, "_mitigated_imbalance", return_value=False),
            patch.object(signal_engine, "_atr", return_value=0.001),
        ):
            result = analyze_market(
                "EURUSD",
                self.quote,
                self.h4,
                self.h1,
                m15=self.m15,
                now=self.now,
            )

        self.assertEqual(result["direction"], "BUY")
        self.assertEqual(result["status"], "STRONG")
        self.assertGreaterEqual(result["quality_score"], 10)
        self.assertEqual(result["quality_score_max"], 13)
        self.assertTrue(result["criteria"]["entry_zone"])
        self.assertTrue(result["criteria"]["risk_reward"])

    def test_medium_signal_does_not_wait_for_every_confirmation(self) -> None:
        flat_m15 = [
            Candle(
                time=candle.time + 100_000,
                open=candle.close,
                high=candle.high,
                low=candle.low,
                close=candle.close,
            )
            for candle in self.m15
        ]
        with (
            patch.object(signal_engine, "_structure_bias", return_value="BUY"),
            patch.object(
                signal_engine, "_liquidity_sweep", return_value=("BUY", 25, 1.0)
            ),
            patch.object(
                signal_engine, "_structure_shift_index", return_value=30
            ),
            patch.object(
                signal_engine, "_mitigated_order_block", return_value=(False, None)
            ) as order_block,
            patch.object(signal_engine, "_mitigated_imbalance", return_value=False),
            patch.object(signal_engine, "_atr", return_value=0.001),
        ):
            result = analyze_market(
                "EURUSD",
                self.quote,
                self.h4,
                self.h1,
                m15=flat_m15,
                now=self.now,
            )

        self.assertEqual(result["direction"], "BUY")
        self.assertEqual(result["status"], "MEDIUM")
        self.assertEqual(result["quality_score"], 9)
        self.assertIsNotNone(result["entry"])
        self.assertIn("Still waiting for", result["reason"])
        self.assertIn("mitigated entry zone", result["reason"])
        self.assertEqual(order_block.call_args.args[0], flat_m15[30:])

    def test_quote_older_than_thirty_seconds_is_stale(self) -> None:
        old_quote = MarketQuote(
            bid=self.quote.bid,
            ask=self.quote.ask,
            time=self.quote.time - 31,
            digits=self.quote.digits,
            point=self.quote.point,
        )
        result = analyze_market(
            "EURUSD",
            old_quote,
            self.h4,
            self.h1,
            now=self.now,
        )
        self.assertEqual(result["status"], "STALE")
        self.assertEqual(result["quote_age_seconds"], 31)

    def test_chart_patterns_include_sweep_fvg_order_block_and_retest(self) -> None:
        frame = candles(40, step=0)
        with (
            patch.object(
                signal_engine, "_liquidity_sweep", return_value=("BUY", 35, 1.0)
            ),
            patch.object(signal_engine, "_latest_fvg", return_value=(1, 0.9, 1.1)),
            patch.object(
                signal_engine, "_latest_order_block", return_value=(0, 0.8, 1.0)
            ),
            patch.object(
                signal_engine, "_structure_retest", return_value=(38, 1.02)
            ),
            patch.object(
                signal_engine, "_structure_shift_index", return_value=36
            ),
            patch.object(signal_engine, "_atr", return_value=1.0),
        ):
            patterns = signal_engine._chart_patterns(
                {"1h": frame},
                price=1.5,
                h4_bias="BUY",
            )

        self.assertEqual(
            {pattern["type"] for pattern in patterns},
            {"liquidity_sweep", "fvg", "order_block", "retest", "entry"},
        )
        self.assertTrue(all(pattern["timeframe"] == "1h" for pattern in patterns))
        retest = next(pattern for pattern in patterns if pattern["type"] == "retest")
        self.assertEqual(retest["level"], 1.02)
        self.assertEqual(
            next(pattern for pattern in patterns if pattern["type"] == "fvg")[
                "entry"
            ],
            1.0,
        )
        self.assertEqual(
            next(pattern for pattern in patterns if pattern["type"] == "fvg")[
                "confluence_score"
            ],
            87,
        )

    def test_chart_patterns_hide_zones_without_aligned_higher_timeframes(self) -> None:
        frame = candles(40, step=0)
        with (
            patch.object(
                signal_engine, "_liquidity_sweep", return_value=("BUY", 35, 1.0)
            ),
            patch.object(signal_engine, "_latest_fvg", return_value=(1, 0.9, 1.1)),
            patch.object(
                signal_engine, "_latest_order_block", return_value=(0, 0.8, 1.0)
            ),
            patch.object(
                signal_engine, "_structure_shift_index", return_value=36
            ),
            patch.object(signal_engine, "_atr", return_value=1.0),
        ):
            patterns = signal_engine._chart_patterns(
                {"1h": frame},
                price=1.5,
                h4_bias="SELL",
            )

        self.assertEqual(patterns, [])

    def test_structure_retest_requires_a_breakout_then_a_reclaim(self) -> None:
        frame = [
            Candle(
                time=index * 60,
                open=9.5,
                high=10.0,
                low=9.0,
                close=9.5,
            )
            for index in range(30)
        ]
        frame[24] = Candle(24 * 60, 9.5, 10.5, 8.5, 10.2)
        frame[25] = Candle(25 * 60, 9.9, 10.3, 9.8, 10.2)
        frame[26] = Candle(26 * 60, 10.1, 10.2, 9.9, 10.05)

        self.assertEqual(
            signal_engine._structure_retest(frame, "BUY", 24),
            (26, 10.0),
        )
        self.assertIsNone(
            signal_engine._structure_retest(frame, "BUY", None),
        )

    def test_incomplete_structure_is_never_promoted_to_buy_or_sell(self) -> None:
        result = analyze_market(
            "EURUSD",
            self.quote,
            self.h4,
            self.h1,
            m15=self.m15,
            now=self.now,
        )
        self.assertEqual(result["direction"], "WAIT")
        self.assertEqual(result["status"], "WAIT")
        self.assertIsNone(result["entry"])
        self.assertEqual(result["quality_score"], 0)

    def test_stale_broker_quote_cannot_produce_a_signal(self) -> None:
        stale_quote = MarketQuote(
            bid=self.quote.bid,
            ask=self.quote.ask,
            time=self.quote.time - 300,
            digits=self.quote.digits,
            point=self.quote.point,
        )
        result = analyze_market(
            "EURUSD",
            stale_quote,
            self.h4,
            self.h1,
            m15=self.m15,
            now=self.now,
        )
        self.assertEqual(result["status"], "STALE")
        self.assertEqual(result["direction"], "WAIT")
        self.assertIsNone(result["entry"])



if __name__ == "__main__":
    unittest.main()
