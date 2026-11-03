from types import SimpleNamespace
from datetime import datetime, timezone
import unittest
from unittest.mock import patch

import server


class ServerTimeOffsetTests(unittest.TestCase):
    def test_removes_future_broker_timezone_offset_from_tick_time(self) -> None:
        now = datetime(2026, 10, 28, 3, 24, tzinfo=timezone.utc)
        broker_tick = int(datetime(2026, 10, 28, 5, 24, tzinfo=timezone.utc).timestamp())

        self.assertEqual(
            server._server_time_offset(broker_tick, local_now=now),
            2 * 60 * 60,
        )

    def test_does_not_adjust_old_or_non_timezone_aligned_ticks(self) -> None:
        now = datetime(2026, 10, 28, 3, 24, tzinfo=timezone.utc)
        old_tick = int(datetime(2026, 10, 28, 1, 24, tzinfo=timezone.utc).timestamp())
        misaligned_future_tick = int(
            datetime(2026, 10, 28, 3, 30, tzinfo=timezone.utc).timestamp()
        )

        self.assertEqual(server._server_time_offset(old_tick, local_now=now), 0)
        self.assertEqual(
            server._server_time_offset(misaligned_future_tick, local_now=now),
            0,
        )




class AccountModeGuardTests(unittest.TestCase):


    def test_automatic_bot_routes_are_not_available(self) -> None:
        for path in ("/api/bot/scan", "/api/bot/run"):
            for method in (server.MarketFeedHandler.do_GET, server.MarketFeedHandler.do_POST):
                handler = server.MarketFeedHandler.__new__(
                    server.MarketFeedHandler
                )
                handler.path = path
                with self.subTest(path=path, method=method.__name__):
                    with patch.object(handler, "_send_json") as send_json:
                        method(handler)
                    send_json.assert_called_once_with(
                        404, {"error": "Endpoint not found."}
                    )

    def test_bot_keeps_high_score_filter_and_accepts_only_seven_or_eight_for_scalping(self) -> None:
        analysis = {
            "direction": "BUY",
            "status": "MEDIUM",
            "quality_score": 9,
            "criteria": {"liquidity_sweep": True},
            "stop_loss": 1.09,
            "take_profit": 1.12,
        }
        self.assertTrue(server._bot_signal_is_eligible(analysis))
        self.assertFalse(server._bot_signal_is_scalping_eligible(analysis))
        analysis["quality_score"] = 8
        self.assertFalse(server._bot_signal_is_eligible(analysis))
        self.assertTrue(server._bot_signal_is_scalping_eligible(analysis))
        analysis["quality_score"] = 7
        self.assertFalse(server._bot_signal_is_eligible(analysis))
        self.assertTrue(server._bot_signal_is_scalping_eligible(analysis))
        analysis["quality_score"] = 6
        self.assertFalse(server._bot_signal_is_scalping_eligible(analysis))
        analysis["quality_score"] = 9
        analysis["criteria"] = {"liquidity_sweep": False}
        self.assertFalse(server._bot_signal_is_eligible(analysis))
        self.assertFalse(server._bot_signal_is_scalping_eligible(analysis))
        analysis["criteria"] = {"liquidity_sweep": True}
        analysis["status"] = "WAIT"
        self.assertFalse(server._bot_signal_is_eligible(analysis))
        self.assertFalse(server._bot_signal_is_scalping_eligible(analysis))

    def test_bot_skips_xauusd_and_uses_configured_pair_list(self) -> None:
        self.assertNotIn("XAUUSD", server.BOT_SYMBOLS)
        self.assertEqual(
            server.BOT_SYMBOLS,
            ("EURUSD", "USDCAD", "GBPUSD", "USDJPY", "AUDUSD", "BTCUSD", "NASDAQ-100"),
        )

    def test_bot_enable_requires_explicit_live_confirmation(self) -> None:
        with (
            patch.object(server, "BOT_ENABLED", False),
            patch.object(server, "ACCOUNT_MODE", "demo"),
        ):
            with self.assertRaisesRegex(RuntimeError, "Explicit confirmation"):
                server._configure_bot(
                    {
                        "account_mode": "live",
                        "enabled": True,
                        "live_confirmation": False,
                    }
                )
        self.assertFalse(server.BOT_ENABLED)

    def test_bot_enable_requires_usd_account_and_trade_permissions(self) -> None:
        account = SimpleNamespace(currency="EUR")
        with (
            patch.object(server, "BOT_ENABLED", False),
            patch.object(server, "ACCOUNT_MODE", "demo"),
            patch.object(server, "_require_mt5_trade_permission", return_value=account),
        ):
            with self.assertRaisesRegex(RuntimeError, "USD-denominated"):
                server._configure_bot(
                    {
                        "account_mode": "demo",
                        "enabled": True,
                        "live_confirmation": False,
                    }
                )
        self.assertFalse(server.BOT_ENABLED)

    def test_bot_enable_in_demo_mode_checks_permissions(self) -> None:
        account = SimpleNamespace(currency="USD")
        with (
            patch.object(server, "BOT_ENABLED", False),
            patch.object(server, "ACCOUNT_MODE", "demo"),
            patch.object(server, "_require_mt5_trade_permission", return_value=account),
        ):
            result = server._configure_bot(
                {
                    "account_mode": "demo",
                    "enabled": True,
                    "live_confirmation": False,
                }
            )
        self.assertTrue(result["enabled"])
        self.assertEqual(result["score_minimum"], 7)
        self.assertEqual(result["high_confirmation_score_minimum"], 9)
        self.assertEqual(result["scalping_position_count"], 2)
        self.assertEqual(result["scalping_target_profit_usd"], 4.0)
        self.assertEqual(result["initial_volume"], 0.10)
        self.assertEqual(result["addon_volume"], 0.01)

    def test_bot_enable_in_live_mode_accepts_explicit_confirmation(self) -> None:
        account = SimpleNamespace(currency="USD")
        with (
            patch.object(server, "BOT_ENABLED", False),
            patch.object(server, "ACCOUNT_MODE", "demo"),
            patch.object(server, "_require_mt5_trade_permission", return_value=account),
        ):
            result = server._configure_bot(
                {
                    "account_mode": "live",
                    "enabled": True,
                    "live_confirmation": True,
                }
            )
        self.assertTrue(result["enabled"])
        self.assertEqual(result["account_mode"], "live")

    def test_bot_disable_does_not_require_a_connected_account(self) -> None:
        with (
            patch.object(server, "BOT_ENABLED", True),
            patch.object(server, "ACCOUNT_MODE", "demo"),
            patch.object(server, "_require_mt5_trade_permission") as check_permission,
        ):
            result = server._configure_bot(
                {
                    "account_mode": "demo",
                    "enabled": False,
                    "live_confirmation": False,
                }
            )
        check_permission.assert_not_called()
        self.assertFalse(result["enabled"])

    def test_bot_setup_comment_uses_closed_candle_time(self) -> None:
        self.assertEqual(
            server._bot_setup_comment(
                {"closed_candle_time_utc": "2026-10-28T12:15:00+00:00"}
            ),
            "ABT1793189700",
        )
        self.assertIsNone(server._bot_setup_comment({"closed_candle_time_utc": "bad"}))

    def test_bot_initial_and_addon_volume_match_spec(self) -> None:
        self.assertEqual(server.BOT_INITIAL_VOLUME, 0.10)
        self.assertEqual(server.BOT_ADDON_VOLUME, 0.01)
        self.assertEqual(server.BOT_MAX_RISK_PERCENT, 0.5)

    def test_bot_price_for_profit_finds_one_dollar_buy_stop(self) -> None:
        with patch.object(
            server.mt5,
            "order_calc_profit",
            side_effect=lambda _kind, _symbol, volume, opened, close: (
                close - opened
            )
            * volume
            * 100,
        ):
            stop = server._bot_price_for_profit(
                server.mt5.ORDER_TYPE_BUY,
                "EURUSD",
                1.0,
                1.0,
                2.0,
                20.0,
            )
        self.assertAlmostEqual(stop, 1.2, places=6)

    def test_bot_price_for_profit_finds_one_dollar_sell_stop(self) -> None:
        with patch.object(
            server.mt5,
            "order_calc_profit",
            side_effect=lambda _kind, _symbol, volume, opened, close: (
                opened - close
            )
            * volume
            * 100,
        ):
            stop = server._bot_price_for_profit(
                server.mt5.ORDER_TYPE_SELL,
                "EURUSD",
                1.0,
                2.0,
                1.0,
                20.0,
            )
        self.assertAlmostEqual(stop, 1.8, places=6)

    def test_bot_scalping_target_price_calculates_four_dollars_for_buy_and_sell(self) -> None:
        def calculate_profit(
            order_type: int,
            _symbol: str,
            volume: float,
            opened: float,
            close: float,
        ) -> float:
            if order_type == server.mt5.ORDER_TYPE_BUY:
                return (close - opened) * 100_000 * volume
            return (opened - close) * 100_000 * volume

        with patch.object(server.mt5, "order_calc_profit", side_effect=calculate_profit):
            buy_target = server._bot_price_for_target_profit(
                order_type=server.mt5.ORDER_TYPE_BUY,
                symbol="EURUSD",
                volume=0.10,
                entry=1.1001,
                target_profit=4.0,
                tick_size=0.00001,
                digits=5,
            )
            sell_target = server._bot_price_for_target_profit(
                order_type=server.mt5.ORDER_TYPE_SELL,
                symbol="EURUSD",
                volume=0.10,
                entry=1.1000,
                target_profit=4.0,
                tick_size=0.00001,
                digits=5,
            )

        self.assertAlmostEqual(buy_target, 1.1005, places=5)
        self.assertAlmostEqual(sell_target, 1.0996, places=5)

    def test_bot_scan_opens_two_four_dollar_scalps_and_preserves_high_score_entry(self) -> None:
        analysis = {
            "direction": "BUY",
            "status": "MEDIUM",
            "quality_score": 7,
            "criteria": {"liquidity_sweep": True},
            "stop_loss": 1.09,
            "take_profit": 1.12,
            "closed_candle_time_utc": "2026-10-28T12:15:00+00:00",
        }
        account = SimpleNamespace(
            margin_mode=server.mt5.ACCOUNT_MARGIN_MODE_RETAIL_HEDGING
        )
        info = SimpleNamespace(name="EURUSD")
        for score, expected_count in ((7, 2), (8, 2), (9, 1)):
            with self.subTest(score=score):
                analysis["quality_score"] = score
                with (
                    patch.object(server, "BOT_SYMBOLS", ("EURUSD",)),
                    patch.object(server, "_BOT_SETUP_STATE", {}),
                    patch.object(
                        server, "_require_mt5_trade_permission", return_value=account
                    ),
                    patch.object(server.mt5, "positions_get", return_value=[]),
                    patch.object(server, "_read_market", return_value=analysis),
                    patch.object(server, "_resolve_symbol", return_value=info),
                    patch.object(server, "_bot_has_entry_comment", return_value=False),
                    patch.object(server, "_bot_place_order", return_value={"volume": 0.1, "risk_amount": 10.0}) as place_order,
                ):
                    server._bot_scan_signals()

                self.assertEqual(place_order.call_count, expected_count)
                for call in place_order.call_args_list:
                    self.assertEqual(call.kwargs["volume"], 0.10)
                    if score in (7, 8):
                        self.assertEqual(
                            call.kwargs["target_profit"],
                            server.BOT_SCALPING_TARGET_PROFIT_USD,
                        )
                        self.assertEqual(
                            call.kwargs["magic"], server.BOT_SCALP_ORDER_MAGIC
                        )
                    else:
                        self.assertIsNone(call.kwargs["target_profit"])
                        self.assertEqual(
                            call.kwargs["target"], analysis["take_profit"]
                        )
                        self.assertEqual(
                            call.kwargs["magic"], server.BOT_ORDER_MAGIC
                        )

    def test_bot_scan_skips_low_score_scalping_on_netting_accounts(self) -> None:
        analysis = {
            "direction": "BUY",
            "status": "MEDIUM",
            "quality_score": 8,
            "criteria": {"liquidity_sweep": True},
            "stop_loss": 1.09,
            "take_profit": 1.12,
            "closed_candle_time_utc": "2026-10-28T12:15:00+00:00",
        }
        account = SimpleNamespace(
            margin_mode=server.mt5.ACCOUNT_MARGIN_MODE_RETAIL_NETTING
        )
        with (
            patch.object(server, "BOT_SYMBOLS", ("EURUSD",)),
            patch.object(server, "_BOT_SETUP_STATE", {}),
            patch.object(server, "_require_mt5_trade_permission", return_value=account),
            patch.object(server.mt5, "positions_get", return_value=[]),
            patch.object(server, "_read_market", return_value=analysis),
            patch.object(server, "_resolve_symbol", return_value=SimpleNamespace(name="EURUSD")),
            patch.object(server, "_bot_place_order") as place_order,
        ):
            server._bot_scan_signals()

        place_order.assert_not_called()

    def test_bot_addon_requires_one_r_progress_and_small_pullback(self) -> None:
        self.assertTrue(
            server._bot_addon_is_ready(
                "BUY", 1.0, 0.1, 1.11, 1.12, 0.03
            )
        )
        self.assertFalse(
            server._bot_addon_is_ready(
                "BUY", 1.0, 0.1, 1.09, 1.12, 0.03
            )
        )
        self.assertFalse(
            server._bot_addon_is_ready(
                "SELL", 1.0, 0.1, 0.89, 0.85, 0.03
            )
        )
        self.assertTrue(
            server._bot_addon_is_ready(
                "SELL", 1.0, 0.1, 0.89, 0.88, 0.03
            )
        )

    def test_bot_detects_only_post_entry_directional_impulse_candles(self) -> None:
        start = int(datetime(2026, 10, 28, 10, tzinfo=timezone.utc).timestamp())
        candles = [
            server.Candle(
                time=start + index * 900,
                open=1.0,
                high=1.001,
                low=0.999,
                close=1.0001,
            )
            for index in range(15)
        ]
        candles.append(
            server.Candle(
                time=start + 15 * 900,
                open=1.0,
                high=1.011,
                low=0.999,
                close=1.01,
            )
        )
        impulse_date = server._bot_impulse_date(
            candles,
            opened_at=start + 14 * 900,
            direction="BUY",
        )
        self.assertEqual(impulse_date, datetime(2026, 10, 28).date())
        self.assertIsNone(
            server._bot_impulse_date(
                candles,
                opened_at=start + 15 * 900,
                direction="BUY",
            )
        )

    def test_bot_initial_order_uses_point_one_lot_and_signal_stop_target(self) -> None:
        account = SimpleNamespace(
            currency="USD",
            balance=10_000.0,
            margin_free=2_000.0,
        )
        info = SimpleNamespace(
            name="EURUSD",
            volume_min=0.01,
            volume_max=100.0,
            volume_step=0.01,
            trade_stops_level=0,
            point=0.00001,
        )
        tick = SimpleNamespace(
            bid=1.1,
            ask=1.1001,
            time=int(datetime.now(timezone.utc).timestamp()),
        )
        order_result = SimpleNamespace(
            retcode=server.mt5.TRADE_RETCODE_DONE,
            order=42,
            deal=43,
            price=1.1001,
        )
        with (
            patch.object(server, "_require_mt5_trade_permission", return_value=account),
            patch.object(server, "_resolve_symbol", return_value=info),
            patch.object(server.mt5, "symbol_info_tick", return_value=tick),
            patch.object(
                server.mt5,
                "order_calc_profit",
                side_effect=lambda _kind, _symbol, volume, entry, close: (
                    close - entry
                )
                * 100_000
                * volume,
            ),
            patch.object(
                server.mt5,
                "order_calc_margin",
                return_value=100.0,
            ),
            patch.object(
                server.mt5,
                "order_check",
                return_value=SimpleNamespace(retcode=0, comment="OK"),
            ),
            patch.object(server.mt5, "order_send", return_value=order_result) as send,
        ):
            result = server._bot_place_order(
                symbol="EURUSD",
                direction="BUY",
                volume=0.10,
                stop=1.099,
                target=1.103,
                comment="ABT1793189700",
                magic=server.BOT_ORDER_MAGIC,
            )

        request = send.call_args.args[0]
        self.assertEqual(request["volume"], 0.10)
        self.assertEqual(request["sl"], 1.099)
        self.assertEqual(request["tp"], 1.103)
        self.assertEqual(request["magic"], server.BOT_ORDER_MAGIC)
        self.assertAlmostEqual(result["risk_amount"], 11.0, places=6)

    def test_bot_order_is_skipped_when_fixed_lot_exceeds_risk_cap(self) -> None:
        account = SimpleNamespace(
            currency="USD",
            balance=1_000.0,
            margin_free=2_000.0,
        )
        info = SimpleNamespace(
            name="EURUSD",
            volume_min=0.01,
            volume_max=100.0,
            volume_step=0.01,
            trade_stops_level=0,
            point=0.00001,
        )
        tick = SimpleNamespace(
            bid=1.1,
            ask=1.1001,
            time=int(datetime.now(timezone.utc).timestamp()),
        )
        with (
            patch.object(server, "_require_mt5_trade_permission", return_value=account),
            patch.object(server, "_resolve_symbol", return_value=info),
            patch.object(server.mt5, "symbol_info_tick", return_value=tick),
            patch.object(
                server.mt5,
                "order_calc_profit",
                side_effect=lambda _kind, _symbol, volume, entry, close: (
                    close - entry
                )
                * 100_000
                * volume,
            ),
            patch.object(server.mt5, "order_send") as send,
        ):
            with self.assertRaisesRegex(RuntimeError, "exceeds the 0.5%"):
                server._bot_place_order(
                    symbol="EURUSD",
                    direction="BUY",
                    volume=0.10,
                    stop=1.09,
                    target=1.12,
                    comment="ABT1793189700",
                    magic=server.BOT_ORDER_MAGIC,
                )
        send.assert_not_called()


    def test_market_feed_includes_position_chart_timeframes(self) -> None:
        info = SimpleNamespace(name="EURUSD", digits=5, point=0.00001)
        tick = SimpleNamespace(bid=1.1, ask=1.1001, time=1_792_766_400)
        rates = [
            {
                "time": 1_792_766_400,
                "open": 1.1,
                "high": 1.101,
                "low": 1.099,
                "close": 1.1005,
            }
        ]
        with (
            patch.object(server, "_require_active_account"),
            patch.object(server, "_resolve_symbol", return_value=info),
            patch.object(server.mt5, "symbol_info_tick", return_value=tick),
            patch.object(server, "_server_time_offset", return_value=7200),
            patch.object(server.mt5, "copy_rates_from_pos", return_value=rates) as copy_rates,
            patch.object(
                server,
                "analyze_market",
                return_value={
                    "direction": "WAIT",
                    "candle_history": {"4h": [], "1h": []},
                },
            ) as analyze_market,
        ):
            result = server._read_market("EURUSD")

        self.assertEqual(
            [
                (call.args[1], call.args[3])
                for call in copy_rates.call_args_list
            ],
            [
                (server.TIMEFRAMES["4h"][0], server.TIMEFRAMES["4h"][1]),
                (server.TIMEFRAMES["1h"][0], server.TIMEFRAMES["1h"][1]),
                (
                    server.TIMEFRAMES["15m"][0],
                    server.MARKET_M15_CANDLE_COUNT,
                ),
                (server.TIMEFRAMES["5m"][0], server.TIMEFRAMES["5m"][1]),
            ],
        )
        self.assertEqual(
            set(result["candle_history"]),
            {"4h", "1h", "15m", "5m"},
        )
        self.assertEqual(len(analyze_market.call_args.kwargs["m15"]), 1)
        self.assertEqual(analyze_market.call_args.args[1].time, tick.time - 7200)
        self.assertEqual(
            analyze_market.call_args.kwargs["m15"][0].time,
            rates[0]["time"] - 7200,
        )



    def test_trade_history_returns_only_bot_tagged_deals(self) -> None:
        def deal(ticket, magic, time_msc, symbol):
            return SimpleNamespace(
                ticket=ticket,
                magic=magic,
                time_msc=time_msc,
                time=time_msc // 1000,
                type=server.mt5.DEAL_TYPE_BUY,
                entry=server.mt5.DEAL_ENTRY_OUT,
                symbol=symbol,
                volume=0.01,
                price=1.1,
                profit=2.0,
                commission=-0.1,
                swap=0.0,
                fee=0.0,
            )

        deals = [
            deal(1, server.BOT_ORDER_MAGIC, 1000, "EURUSD"),
            deal(2, server.MANUAL_ORDER_MAGIC, 3000, "GBPUSD"),
            deal(3, server.BOT_ORDER_MAGIC, 2000, "BTCUSD"),
            deal(4, server.BOT_ADDON_ORDER_MAGIC, 2500, "USDCAD"),
        ]
        account = SimpleNamespace(currency="USD")
        with (
            patch.object(server, "_require_active_account", return_value=account),
            patch.object(server.mt5, "history_deals_get", return_value=deals),
        ):
            result = server._trade_history()

        self.assertEqual([item["ticket"] for item in result["deals"]], [4, 3, 1])
        self.assertTrue(all(item["automated"] for item in result["deals"]))

    def test_btc_and_nasdaq_are_supported_markets(self) -> None:
        self.assertIn("BTCUSD", server.SYMBOLS)
        self.assertIn("NASDAQ-100", server.SYMBOLS)

    def test_nasdaq_hyphenated_broker_symbol_resolves_exactly(self) -> None:
        info = SimpleNamespace(name="NASDAQ-100")
        with (
            patch.object(
                server.mt5,
                "symbols_get",
                return_value=[SimpleNamespace(name="NASDAQ-100")],
            ),
            patch.object(server.mt5, "symbol_select", return_value=True),
            patch.object(server.mt5, "symbol_info", return_value=info),
        ):
            self.assertIs(server._resolve_symbol("NASDAQ-100"), info)

    def test_connect_account_logs_in_and_returns_account_summary(self) -> None:
        account = SimpleNamespace(
            login=123456,
            trade_mode=server.mt5.ACCOUNT_TRADE_MODE_DEMO,
        )
        summary = {"login": 123456, "account_mode": "demo"}
        with (
            patch.object(server, "ORDER_REVIEW_ENABLED", True),
            patch.object(server, "ACCOUNT_MODE", "demo"),
            patch.object(server.mt5, "login", return_value=True) as login,
            patch.object(server, "_require_connected_account", return_value=account),
            patch.object(server, "_account_summary", return_value=summary),
        ):
            result = server._connect_account(
                {
                    "login": "123456",
                    "password": "test-password",
                    "server": "Broker-Demo",
                    "account_mode": "demo",
                }
            )

        login.assert_called_once_with(
            123456,
            password="test-password",
            server="Broker-Demo",
        )
        self.assertEqual(result, summary)

    def test_connect_account_rejects_wrong_mode_and_disables_automation(self) -> None:
        account = SimpleNamespace(
            login=123456,
            trade_mode=server.mt5.ACCOUNT_TRADE_MODE_REAL,
        )
        with (
            patch.object(server, "ORDER_REVIEW_ENABLED", True),
            patch.object(server, "BOT_ENABLED", True),
            patch.object(server, "ACCOUNT_MODE", "demo"),
            patch.object(server.mt5, "login", return_value=True),
            patch.object(server, "_require_connected_account", return_value=account),
        ):
            with self.assertRaisesRegex(RuntimeError, "live account"):
                server._connect_account(
                    {
                        "login": "123456",
                        "password": "test-password",
                        "server": "Broker-Live",
                        "account_mode": "demo",
                    }
                )
            self.assertFalse(server.ORDER_REVIEW_ENABLED)
            self.assertFalse(server.BOT_ENABLED)
            self.assertEqual(server.ACCOUNT_MODE, "demo")

    def test_connect_account_reinitializes_terminal_after_login_failure(self) -> None:
        account = SimpleNamespace(
            login=123456,
            trade_mode=server.mt5.ACCOUNT_TRADE_MODE_DEMO,
        )
        with (
            patch.object(server, "ORDER_REVIEW_ENABLED", True),
            patch.object(server, "ACCOUNT_MODE", "demo"),
            patch.object(server.mt5, "login", return_value=False),
            patch.object(server.mt5, "last_error", return_value=(-6, "No connection")),
            patch.object(server.mt5, "shutdown") as shutdown,
            patch.object(server.mt5, "initialize", return_value=True) as initialize,
            patch.object(server, "_require_connected_account", return_value=account),
            patch.object(server, "_account_summary", return_value={"login": 123456}),
        ):
            result = server._connect_account(
                {
                    "login": "123456",
                    "password": "test-password",
                    "server": "Broker-Demo",
                    "account_mode": "demo",
                }
            )

        shutdown.assert_called_once()
        initialize.assert_called_once_with(
            server.TERMINAL_PATH,
            login=123456,
            password="test-password",
            server="Broker-Demo",
            timeout=30_000,
        )
        self.assertEqual(result, {"login": 123456})

    def test_connect_account_reports_reconnect_failure_without_password(self) -> None:
        with (
            patch.object(server, "ORDER_REVIEW_ENABLED", True),
            patch.object(server, "ACCOUNT_MODE", "demo"),
            patch.object(server.mt5, "login", return_value=False),
            patch.object(server.mt5, "last_error", side_effect=[
                (-6, "No connection"),
                (-10005, "IPC timeout"),
            ]),
            patch.object(server.mt5, "shutdown"),
            patch.object(server.mt5, "initialize", return_value=False),
        ):
            with self.assertRaises(RuntimeError) as error:
                server._connect_account(
                    {
                        "login": "123456",
                        "password": "secret-test-password",
                        "server": "Broker-Demo",
                        "account_mode": "demo",
                    }
                )

        self.assertIn("terminal reconnect error", str(error.exception))
        self.assertIn("IPC timeout", str(error.exception))
        self.assertNotIn("secret-test-password", str(error.exception))

    def test_connect_account_rejects_malformed_credentials(self) -> None:
        with patch.object(server.mt5, "login") as login:
            with self.assertRaisesRegex(ValueError, "numeric MT5 account"):
                server._connect_account(
                    {
                        "login": "not-a-number",
                        "password": "test-password",
                        "server": "Broker-Demo",
                        "account_mode": "demo",
                    }
                )
        login.assert_not_called()

    def test_manual_order_review_can_be_disabled_without_an_account(self) -> None:
        with (
            patch.object(server, "ORDER_REVIEW_ENABLED", True),
            patch.object(server, "ORDER_REVIEW_RISK_PERCENT", 0.5),
            patch.object(server, "ACCOUNT_MODE", "live"),
            patch.object(server, "_require_active_account") as require_account,
        ):
            result = server._configure_order_review(
                {
                    "account_mode": "demo",
                    "enabled": False,
                    "risk_percent": 0.25,
                }
            )

        require_account.assert_not_called()
        self.assertEqual(
            result,
            {"account_mode": "demo", "enabled": False, "risk_percent": 0.25},
        )

    def test_enabling_manual_order_review_checks_mt5_permissions(self) -> None:
        account = SimpleNamespace(trade_allowed=True)
        terminal = SimpleNamespace(trade_allowed=True)
        with (
            patch.object(server, "ORDER_REVIEW_ENABLED", False),
            patch.object(server, "ORDER_REVIEW_RISK_PERCENT", 0.5),
            patch.object(server, "ACCOUNT_MODE", "demo"),
            patch.object(server, "_require_active_account", return_value=account),
            patch.object(server.mt5, "terminal_info", return_value=terminal),
        ):
            result = server._configure_order_review(
                {
                    "account_mode": "demo",
                    "enabled": True,
                    "risk_percent": 0.25,
                }
            )

        self.assertEqual(
            result,
            {"account_mode": "demo", "enabled": True, "risk_percent": 0.25},
        )


    def test_live_mode_rejects_a_demo_account(self) -> None:
        account = SimpleNamespace(trade_mode=server.mt5.ACCOUNT_TRADE_MODE_DEMO)
        with (
            patch.object(server, "_require_connected_account", return_value=account),
            patch.object(server, "ACCOUNT_MODE", "live"),
        ):
            with self.assertRaisesRegex(RuntimeError, "Select a live account"):
                server._require_active_account()

    def test_live_mode_accepts_a_real_account(self) -> None:
        account = SimpleNamespace(trade_mode=server.mt5.ACCOUNT_TRADE_MODE_REAL)
        with (
            patch.object(server, "_require_connected_account", return_value=account),
            patch.object(server, "ACCOUNT_MODE", "live"),
        ):
            self.assertIs(server._require_active_account(), account)

    def test_demo_mode_accepts_a_demo_account(self) -> None:
        account = SimpleNamespace(trade_mode=server.mt5.ACCOUNT_TRADE_MODE_DEMO)
        with (
            patch.object(server, "_require_connected_account", return_value=account),
            patch.object(server, "ACCOUNT_MODE", "demo"),
        ):
            self.assertIs(server._require_active_account(), account)

    def test_order_preview_rejects_unsupported_symbol(self) -> None:
        with patch.object(server, "_require_order_permission"):
            with self.assertRaisesRegex(ValueError, "supported symbol"):
                server._make_order_preview(
                    {
                        "symbol": "UNKNOWN",
                        "direction": "BUY",
                        "risk_percent": 0.25,
                    }
                )

    def test_order_preview_rejects_risk_above_hard_cap(self) -> None:
        with patch.object(server, "_require_order_permission"):
            with self.assertRaisesRegex(ValueError, "limited to 0.5%"):
                server._make_order_preview(
                    {
                        "symbol": "EURUSD",
                        "direction": "BUY",
                        "risk_percent": 0.51,
                    }
                )








    def test_medium_market_signal_can_be_manually_reviewed_with_risk_cap(self) -> None:
        account = SimpleNamespace(
            balance=10_000.0,
            currency="USD",
            margin_free=1_000.0,
        )
        info = SimpleNamespace(
            name="EURUSD",
            point=0.00001,
            trade_stops_level=10,
            volume_step=0.01,
            volume_min=0.01,
            volume_max=100.0,
        )
        tick = SimpleNamespace(bid=1.1000, ask=1.1001)

        with (
            patch.object(server, "_require_order_permission", return_value=account),
            patch.object(
                server,
                "_read_market",
                return_value={
                    "direction": "BUY",
                    "status": "MEDIUM",
                    "stop_loss": 1.0990,
                    "take_profit": 1.1023,
                    "quality_score": 8,
                    "quality_score_max": 13,
                },
            ),
            patch.object(server, "_resolve_symbol", return_value=info),
            patch.object(server.mt5, "symbol_info_tick", return_value=tick),
            patch.object(
                server.mt5,
                "order_calc_profit",
                side_effect=lambda _type, _symbol, volume, entry, close: (
                    close - entry
                )
                * 100_000
                * volume,
            ),
            patch.object(
                server.mt5,
                "order_calc_margin",
                side_effect=lambda _type, _symbol, volume, _price: volume * 1_000,
            ),
            patch.object(server.mt5, "positions_get", return_value=[]),
        ):
            preview = server._make_order_preview(
                {
                    "symbol": "EURUSD",
                    "direction": "BUY",
                    "risk_percent": 0.5,
                }
            )

        self.assertEqual(preview["volume"], server.MAX_ORDER_VOLUME)
        self.assertLessEqual(preview["risk_amount"], account.balance * 0.005)
        self.assertEqual(preview["score"], 8)
        self.assertEqual(preview["score_max"], 13)













    def test_trade_authorization_requires_the_exact_bearer_token(self) -> None:
        handler = SimpleNamespace(
            headers={"Authorization": "Bearer session-token"}
        )
        with patch.object(server, "TRADE_TOKEN", "session-token"):
            self.assertTrue(server.MarketFeedHandler._authorized(handler))
            handler.headers = {"Authorization": "session-token"}
            self.assertFalse(server.MarketFeedHandler._authorized(handler))
        with patch.object(server, "TRADE_TOKEN", None):
            handler.headers = {"Authorization": "Bearer session-token"}
            self.assertFalse(server.MarketFeedHandler._authorized(handler))


if __name__ == "__main__":
    unittest.main()
