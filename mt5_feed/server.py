"""Local MT5 market feed and session-authorized manual and bot order bridge."""

from __future__ import annotations

import argparse
import hmac
import json
import logging
import math
import os
import secrets
import sys
import threading
import time
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

try:
    import MetaTrader5 as mt5
except ImportError as error:
    raise SystemExit(
        "MetaTrader5 Python integration is required. Run "
        "`python -m pip install -r mt5_feed/requirements.txt`."
    ) from error

from signal_engine import (
    Candle,
    MarketQuote,
    _atr,
    analyze_market,
)

LOG = logging.getLogger("aurum_market_feed")
TIMEFRAMES = {
    "4h": (mt5.TIMEFRAME_H4, 160),
    "1h": (mt5.TIMEFRAME_H1, 220),
    "15m": (mt5.TIMEFRAME_M15, 160),
    "5m": (mt5.TIMEFRAME_M5, 120),
    "1m": (mt5.TIMEFRAME_M1, 180),
}
SYMBOLS = (
    "EURUSD",
    "USDCAD",
    "GBPUSD",
    "USDJPY",
    "XAUUSD",
    "AUDUSD",
    "BTCUSD",
    "NASDAQ-100",
)
MAX_ORDER_RISK_PERCENT = 0.5
MAX_ORDER_VOLUME = 0.01
MAX_OPEN_POSITIONS_LIMIT = 5
BOT_ORDER_MAGIC = 2701024
BOT_TEMP_ORDER_MAGIC = 2701025
BOT_ADDON_ORDER_MAGIC = 2701026
BOT_SCALP_ORDER_MAGIC = 2701027
BOT_ORDER_MAGICS = frozenset(
    (
        BOT_ORDER_MAGIC,
        BOT_TEMP_ORDER_MAGIC,
        BOT_ADDON_ORDER_MAGIC,
        BOT_SCALP_ORDER_MAGIC,
    )
)
MANUAL_ORDER_MAGIC = 2701023
POSITION_CHART_SYMBOLS = ("EURUSD", "USDCAD", "XAUUSD")
BOT_SYMBOLS = tuple(symbol for symbol in SYMBOLS if symbol != "XAUUSD")
MARKET_M15_CANDLE_COUNT = 500
BOT_SCORE_MINIMUM = 9
BOT_SCALPING_SCORE_MINIMUM = 7
BOT_SCALPING_SCORE_MAXIMUM = 8
BOT_SCALPING_POSITION_COUNT = 2
BOT_SCALPING_TARGET_PROFIT_USD = 4.0
BOT_INITIAL_VOLUME = 0.10
BOT_ADDON_VOLUME = 0.01
BOT_MAX_RISK_PERCENT = 0.5
BOT_SCAN_INTERVAL_SECONDS = 15
TRADE_TOKEN = os.environ.get("AURUM_TRADING_TOKEN")
ACCOUNT_MODE = os.environ.get("AURUM_ACCOUNT_MODE", "demo")
ORDER_REVIEW_ENABLED = False
ORDER_REVIEW_RISK_PERCENT = 0.5
BOT_ENABLED = False
_ORDER_PREVIEWS: dict[str, dict[str, object]] = {}
_ORDER_PREVIEWS_LOCK = threading.Lock()
_ORDER_EXECUTION_LOCK = threading.Lock()
_ACCOUNT_CONFIG_LOCK = threading.Lock()
_ACCOUNT_CONNECT_LOCK = threading.Lock()
_BOT_SETUP_STATE: dict[str, dict[str, object]] = {}
_BOT_STOP = threading.Event()
TERMINAL_PATH = os.environ.get(
    "MT5_TERMINAL_PATH",
    r"C:\Program Files\Headway MT5 Terminal\terminal64.exe",
)


def _is_bot_order_magic(magic: object) -> bool:
    return (
        not isinstance(magic, bool)
        and isinstance(magic, int)
        and magic in BOT_ORDER_MAGICS
    )


def _resolve_symbol(base_name: str) -> Any:
    symbols = mt5.symbols_get()
    if symbols is None:
        raise RuntimeError(f"Cannot read broker symbols: {mt5.last_error()}")
    matching = [item.name for item in symbols if item.name.startswith(base_name)]
    if base_name in matching:
        selected = base_name
    elif len(matching) == 1:
        selected = matching[0]
    else:
        raise RuntimeError(
            f"Cannot uniquely find {base_name} in the broker symbol list."
        )
    if not mt5.symbol_select(selected, True):
        raise RuntimeError(
            f"Cannot enable market quotes for {selected}: {mt5.last_error()}"
        )
    info = mt5.symbol_info(selected)
    if info is None:
        raise RuntimeError(f"Cannot read broker metadata for {selected}.")
    return info


def _require_connected_account() -> Any:
    account = mt5.account_info()
    if account is None:
        raise RuntimeError(f"MetaTrader account is unavailable: {mt5.last_error()}")
    terminal = mt5.terminal_info()
    if terminal is None or not terminal.connected:
        raise RuntimeError("The MetaTrader 5 terminal is disconnected.")
    return account


def _require_active_account() -> Any:
    account = _require_connected_account()
    expected_mode = (
        mt5.ACCOUNT_TRADE_MODE_DEMO
        if ACCOUNT_MODE == "demo"
        else mt5.ACCOUNT_TRADE_MODE_REAL
    )
    if account.trade_mode != expected_mode:
        raise RuntimeError(
            f"Select a {ACCOUNT_MODE} account in MetaTrader 5 and restart or reconnect the feed."
        )
    return account


def _require_order_permission() -> Any:
    if not ORDER_REVIEW_ENABLED:
        raise RuntimeError("Enable manual order review before submitting an order.")
    return _require_mt5_trade_permission()


def _require_mt5_trade_permission() -> Any:
    account = _require_active_account()
    if not account.trade_allowed:
        raise RuntimeError("Trading is disabled for the active MetaTrader account.")
    terminal = mt5.terminal_info()
    if terminal is None or not terminal.trade_allowed:
        raise RuntimeError("Enable algorithmic trading in MetaTrader 5 to continue.")
    return account


def _account_summary() -> dict[str, object]:
    account = _require_active_account()
    positions = mt5.positions_get()
    if positions is None:
        raise RuntimeError(f"Cannot read open positions: {mt5.last_error()}")
    return {
        "login": int(account.login),
        "server": account.server,
        "account_mode": ACCOUNT_MODE,
        "currency": account.currency,
        "balance": float(account.balance),
        "equity": float(account.equity),
        "profit": float(account.profit),
        "margin": float(account.margin),
        "free_margin": float(account.margin_free),
        "positions": [
            {
                "ticket": int(position.ticket),
                "symbol": position.symbol,
                "direction": (
                    "BUY"
                    if position.type == mt5.POSITION_TYPE_BUY
                    else "SELL"
                ),
                "volume": float(position.volume),
                "open_price": float(position.price_open),
                "stop_loss": float(position.sl),
                "take_profit": float(position.tp),
                "profit": float(position.profit),
            }
            for position in positions
        ],
    }


def _trade_history() -> dict[str, object]:
    account = _require_active_account()
    end = datetime.now(timezone.utc)
    start = end - timedelta(days=30)
    deals = mt5.history_deals_get(start, end)
    if deals is None:
        raise RuntimeError(f"Cannot read MetaTrader trade history: {mt5.last_error()}")
    rows = []
    bot_deals = [
        deal
        for deal in sorted(deals, key=lambda item: item.time_msc, reverse=True)
        if _is_bot_order_magic(deal.magic)
    ][:200]
    for deal in bot_deals:
        if deal.type == mt5.DEAL_TYPE_BUY:
            direction = "BUY"
        elif deal.type == mt5.DEAL_TYPE_SELL:
            direction = "SELL"
        else:
            direction = "OTHER"
        entry_names = {
            mt5.DEAL_ENTRY_IN: "IN",
            mt5.DEAL_ENTRY_OUT: "OUT",
            mt5.DEAL_ENTRY_INOUT: "INOUT",
            mt5.DEAL_ENTRY_OUT_BY: "OUT BY",
        }
        rows.append(
            {
                "ticket": int(deal.ticket),
                "time_utc": datetime.fromtimestamp(
                    deal.time, timezone.utc
                ).isoformat(),
                "symbol": deal.symbol or "—",
                "direction": direction,
                "entry": entry_names.get(deal.entry, "OTHER"),
                "volume": float(deal.volume),
                "price": float(deal.price),
                "profit": float(deal.profit),
                "commission": float(deal.commission),
                "swap": float(deal.swap),
                "fee": float(deal.fee),
                "net_profit": float(
                    deal.profit + deal.commission + deal.swap + deal.fee
                ),
                "currency": account.currency,
                "automated": True,
            }
        )
    return {
        "account_mode": ACCOUNT_MODE,
        "currency": account.currency,
        "days": 30,
        "deals": rows,
    }


def _login_with_fallback(login: int, password: str, *, server: str) -> bool:
    if mt5.login(login, password=password, server=server):
        return True

    login_error = mt5.last_error()
    mt5.shutdown()
    if mt5.initialize(
        TERMINAL_PATH,
        login=login,
        password=password,
        server=server,
        timeout=30_000,
    ):
        return True

    initialize_error = mt5.last_error()
    raise RuntimeError(
        "MetaTrader could not sign in to this account. "
        f"Login error: {login_error}; terminal reconnect error: "
        f"{initialize_error}. Check the numeric login, MT5 trading password, "
        "exact broker server name, selected Demo/Live mode, and that this "
        "terminal can reach the broker."
    )


def _connect_account(payload: dict[str, object]) -> dict[str, object]:
    global ACCOUNT_MODE, BOT_ENABLED, ORDER_REVIEW_ENABLED

    raw_login = payload.get("login")
    password = payload.get("password")
    server = payload.get("server")
    mode = payload.get("account_mode")
    if (
        isinstance(raw_login, bool)
        or not isinstance(raw_login, (str, int))
        or not str(raw_login).isdecimal()
        or int(raw_login) <= 0
    ):
        raise ValueError("Enter the numeric MT5 account login.")
    if not isinstance(password, str) or not password or len(password) > 256:
        raise ValueError("Enter the MT5 trading password.")
    if not isinstance(server, str) or not server.strip() or len(server) > 128:
        raise ValueError("Enter the exact broker server name shown in MT5.")
    if mode not in ("demo", "live"):
        raise ValueError("Choose Demo or Live account mode.")

    login = int(raw_login)
    server = server.strip()
    with _ACCOUNT_CONNECT_LOCK:
        with _ORDER_EXECUTION_LOCK:
            with _ACCOUNT_CONFIG_LOCK:
                ORDER_REVIEW_ENABLED = False
                BOT_ENABLED = False
                _BOT_SETUP_STATE.clear()
                if not _login_with_fallback(
                    login,
                    password=password,
                    server=server,
                ):
                    raise RuntimeError(
                        f"MetaTrader login failed: {mt5.last_error()}"
                    )
                account = _require_connected_account()
                if int(account.login) != login:
                    raise RuntimeError(
                        "MetaTrader connected a different account than the requested login."
                    )
                expected_mode = (
                    mt5.ACCOUNT_TRADE_MODE_DEMO
                    if mode == "demo"
                    else mt5.ACCOUNT_TRADE_MODE_REAL
                )
                if account.trade_mode != expected_mode:
                    actual_mode = (
                        "demo"
                        if account.trade_mode == mt5.ACCOUNT_TRADE_MODE_DEMO
                        else "live"
                        if account.trade_mode == mt5.ACCOUNT_TRADE_MODE_REAL
                        else "unsupported"
                    )
                    raise RuntimeError(
                        f"This login is a {actual_mode} account, not the selected {mode} account. "
                        "Choose the matching mode and connect again."
                    )
                ACCOUNT_MODE = mode

    LOG.info("Connected MT5 account %d on %s (%s mode).", login, server, mode)
    return _account_summary()


def _make_order_preview(payload: dict[str, object]) -> dict[str, object]:
    account = _require_order_permission()
    symbol = payload.get("symbol")
    direction = payload.get("direction")
    risk_percent = payload.get("risk_percent")
    if symbol not in SYMBOLS or direction not in ("BUY", "SELL"):
        raise ValueError("Choose a supported symbol and a current BUY or SELL signal.")
    if isinstance(risk_percent, bool) or not isinstance(risk_percent, (int, float)):
        raise ValueError("Risk per trade must be a number.")
    if not math.isfinite(risk_percent) or not 0 < risk_percent <= MAX_ORDER_RISK_PERCENT:
        raise ValueError(
            f"Orders are limited to {MAX_ORDER_RISK_PERCENT}% estimated risk per trade."
        )
    if risk_percent > ORDER_REVIEW_RISK_PERCENT:
        raise ValueError("The order exceeds the configured manual review risk limit.")

    analysis = _read_market(symbol)
    if (
        analysis["direction"] != direction
        or analysis["status"] not in ("STRONG", "VALID", "MEDIUM")
    ):
        raise RuntimeError(
            "The signal changed or is no longer valid. Refresh and review it again."
        )

    info = _resolve_symbol(symbol)
    order_type = (
        mt5.ORDER_TYPE_BUY if direction == "BUY" else mt5.ORDER_TYPE_SELL
    )
    tick = mt5.symbol_info_tick(info.name)
    if tick is None:
        raise RuntimeError(f"Cannot read the latest quote for {info.name}.")
    entry = float(tick.ask) if direction == "BUY" else float(tick.bid)
    raw_stop = analysis.get("stop_loss")
    raw_target = analysis.get("take_profit")
    if not isinstance(raw_stop, (int, float)) or not isinstance(
        raw_target, (int, float)
    ):
        raise RuntimeError("The current signal does not include valid stop and target prices.")
    stop = float(raw_stop)
    target = float(raw_target)
    minimum_distance = int(info.trade_stops_level) * float(info.point)
    if not all(math.isfinite(value) for value in (entry, stop, target)):
        raise RuntimeError("The current signal contains an invalid price.")
    if direction == "BUY":
        if not stop < entry - minimum_distance or (
            target != 0.0 and not target > entry + minimum_distance
        ):
            raise RuntimeError("The signal's stop or target is invalid for the current broker quote.")
    elif (
        (target != 0.0 and not target < entry - minimum_distance)
        or not stop > entry + minimum_distance
    ):
        raise RuntimeError("The signal's stop or target is invalid for the current broker quote.")

    one_lot_loss = mt5.order_calc_profit(order_type, info.name, 1.0, entry, stop)
    if one_lot_loss is None or not math.isfinite(float(one_lot_loss)):
        raise RuntimeError(f"Cannot calculate order risk: {mt5.last_error()}")
    one_lot_loss = abs(float(one_lot_loss))
    if one_lot_loss <= 0:
        raise RuntimeError("Cannot calculate a positive stop-loss risk for this order.")
    balance = float(account.balance)
    if not math.isfinite(balance) or balance <= 0:
        raise RuntimeError("The selected account balance is unavailable for risk sizing.")
    risk_amount = balance * float(risk_percent) / 100
    step = float(info.volume_step)
    minimum_volume = float(info.volume_min)
    maximum_volume = min(float(info.volume_max), MAX_ORDER_VOLUME)
    if step <= 0 or minimum_volume > maximum_volume:
        raise RuntimeError("This broker symbol does not support the configured volume limit.")
    raw_volume = min(risk_amount / one_lot_loss, maximum_volume)
    volume = math.floor((raw_volume + step * 1e-9) / step) * step
    volume = round(volume, 8)
    if volume < minimum_volume:
        raise RuntimeError(
            "The minimum broker volume would exceed your selected risk limit."
        )
    actual_risk = mt5.order_calc_profit(order_type, info.name, volume, entry, stop)
    if (
        actual_risk is None
        or not math.isfinite(float(actual_risk))
        or abs(float(actual_risk)) > risk_amount * 1.001
    ):
        raise RuntimeError("The minimum order size exceeds your selected risk limit.")
    margin = mt5.order_calc_margin(order_type, info.name, volume, entry)
    if margin is None or not math.isfinite(float(margin)) or float(margin) < 0:
        raise RuntimeError(f"Cannot calculate required margin: {mt5.last_error()}")
    if float(margin) > float(account.margin_free):
        raise RuntimeError("There is not enough free margin for this order.")

    positions = mt5.positions_get()
    if positions is None:
        raise RuntimeError(f"Cannot check existing positions: {mt5.last_error()}")
    if len(positions) >= MAX_OPEN_POSITIONS_LIMIT:
        raise RuntimeError(
            f"Order limit reached ({MAX_OPEN_POSITIONS_LIMIT} open positions)."
        )
    if any(position.symbol == info.name for position in positions):
        raise RuntimeError(f"A position is already open for {info.name}.")

    now = time.time()
    preview = {
        "preview_id": secrets.token_urlsafe(24),
        "symbol": info.name,
        "direction": direction,
        "volume": volume,
        "risk_percent": float(risk_percent),
        "risk_amount": abs(float(actual_risk)),
        "currency": account.currency,
        "entry": entry,
        "stop_loss": stop,
        "take_profit": target,
        "score": int(analysis["quality_score"]),
        "score_max": int(analysis.get("quality_score_max", 100)),
        "expires_at": now + 30,
    }
    with _ORDER_PREVIEWS_LOCK:
        _ORDER_PREVIEWS[preview["preview_id"]] = preview
        for key, value in list(_ORDER_PREVIEWS.items()):
            if float(value["expires_at"]) < now:
                del _ORDER_PREVIEWS[key]
    return {key: value for key, value in preview.items() if key != "expires_at"}

def _execute_demo_order(payload: dict[str, object]) -> dict[str, object]:
    with _ORDER_EXECUTION_LOCK:
        return _execute_demo_order_locked(payload)


def _execute_demo_order_locked(payload: dict[str, object]) -> dict[str, object]:
    _require_order_permission()
    preview_id = payload.get("preview_id")
    if not isinstance(preview_id, str):
        raise ValueError("A reviewed order preview is required.")
    with _ORDER_PREVIEWS_LOCK:
        preview = _ORDER_PREVIEWS.pop(preview_id, None)
    if preview is None or float(preview["expires_at"]) < time.time():
        raise RuntimeError("This order preview expired or was already used. Review a new order.")

    refreshed = _make_order_preview(
        {
            "symbol": next(
                base for base in SYMBOLS if str(preview["symbol"]).startswith(base)
            ),
            "direction": preview["direction"],
            "risk_percent": preview["risk_percent"],
        }
    )
    with _ORDER_PREVIEWS_LOCK:
        _ORDER_PREVIEWS.pop(str(refreshed["preview_id"]), None)
    if (
        refreshed["volume"] != preview["volume"]
        or refreshed["risk_amount"] > float(preview["risk_amount"]) * 1.001
        or abs(float(refreshed["entry"]) - float(preview["entry"]))
        > max(abs(float(preview["entry"]) - float(preview["stop_loss"])) * 0.02, 1e-8)
    ):
        raise RuntimeError("Market price or order risk changed. Review a fresh order preview.")

    order_type = (
        mt5.ORDER_TYPE_BUY
        if preview["direction"] == "BUY"
        else mt5.ORDER_TYPE_SELL
    )
    request = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": preview["symbol"],
        "volume": preview["volume"],
        "type": order_type,
        "price": refreshed["entry"],
        "sl": refreshed["stop_loss"],
        "tp": refreshed["take_profit"],
        "deviation": 20,
        "magic": MANUAL_ORDER_MAGIC,
        "comment": "ARTIFACTS manual",
        "type_time": mt5.ORDER_TIME_GTC,
    }
    check_errors = []
    result = None
    for filling_mode in (mt5.ORDER_FILLING_IOC, mt5.ORDER_FILLING_FOK):
        request["type_filling"] = filling_mode
        check = mt5.order_check(request)
        if check is None or check.retcode != 0:
            check_errors.append(
                check.comment if check is not None else str(mt5.last_error())
            )
            continue
        _require_order_permission()
        result = mt5.order_send(request)
        break
    if result is None and check_errors:
        raise RuntimeError(
            "MetaTrader rejected the order check: " + "; ".join(check_errors)
        )
    successful_codes = {
        mt5.TRADE_RETCODE_DONE,
        mt5.TRADE_RETCODE_DONE_PARTIAL,
        mt5.TRADE_RETCODE_PLACED,
    }
    if result is None or result.retcode not in successful_codes:
        reason = result.comment if result is not None else mt5.last_error()
        raise RuntimeError(f"MetaTrader did not execute the order: {reason}")
    LOG.warning(
        "Confirmed order: %s %s %.2f lots; order=%s",
        preview["direction"],
        preview["symbol"],
        float(preview["volume"]),
        result.order,
    )
    return {
        "order": int(result.order),
        "deal": int(result.deal),
        "symbol": preview["symbol"],
        "direction": preview["direction"],
        "strategy": None,
        "volume": float(preview["volume"]),
        "price": float(result.price),
        "risk_amount": float(preview["risk_amount"]),
        "currency": preview["currency"],
        "temporary": False,
    }

def _configure_order_review(payload: dict[str, object]) -> dict[str, object]:
    global ACCOUNT_MODE, ORDER_REVIEW_ENABLED, ORDER_REVIEW_RISK_PERCENT

    mode = payload.get("account_mode")
    enabled = payload.get("enabled")
    risk_percent = payload.get("risk_percent")
    if mode not in ("demo", "live") or not isinstance(enabled, bool):
        raise ValueError("Choose Demo or Live and set manual order review state.")
    if (
        isinstance(risk_percent, bool)
        or not isinstance(risk_percent, (int, float))
        or not math.isfinite(risk_percent)
        or not 0 < risk_percent <= MAX_ORDER_RISK_PERCENT
    ):
        raise ValueError(
            f"Per-order risk must be above zero and no more than {MAX_ORDER_RISK_PERCENT}%."
        )

    previous_mode = ACCOUNT_MODE
    ACCOUNT_MODE = mode
    try:
        if enabled:
            account = _require_active_account()
            if not account.trade_allowed:
                raise RuntimeError(
                    "Trading is disabled for the active MetaTrader account."
                )
            terminal = mt5.terminal_info()
            if terminal is None or not terminal.trade_allowed:
                raise RuntimeError(
                    "Enable algorithmic trading in MetaTrader 5 to review orders."
                )
    except Exception:
        ACCOUNT_MODE = previous_mode
        raise

    ORDER_REVIEW_RISK_PERCENT = float(risk_percent)
    ORDER_REVIEW_ENABLED = enabled
    return {
        "account_mode": ACCOUNT_MODE,
        "enabled": ORDER_REVIEW_ENABLED,
        "risk_percent": ORDER_REVIEW_RISK_PERCENT,
    }


def _configure_bot(payload: dict[str, object]) -> dict[str, object]:
    global ACCOUNT_MODE, BOT_ENABLED

    mode = payload.get("account_mode")
    enabled = payload.get("enabled")
    live_confirmation = payload.get("live_confirmation", False)
    if mode not in ("demo", "live") or not isinstance(enabled, bool):
        raise ValueError("Choose Demo or Live and set bot state.")
    if not isinstance(live_confirmation, bool):
        raise ValueError("Live confirmation must be a boolean.")
    if enabled and mode == "live" and not live_confirmation:
        raise RuntimeError("Explicit confirmation is required to enable live bot trading.")

    with _ORDER_EXECUTION_LOCK:
        previous_mode = ACCOUNT_MODE
        ACCOUNT_MODE = mode
        try:
            if enabled:
                account = _require_mt5_trade_permission()
                if account.currency != "USD":
                    raise RuntimeError(
                        "The bot requires a USD-denominated account for its dollar-based risk and stop rules."
                    )
            BOT_ENABLED = enabled
        except Exception:
            ACCOUNT_MODE = previous_mode
            raise

    if enabled:
        LOG.warning(
            "Automated bot enabled in %s mode; XAUUSD is excluded.",
            ACCOUNT_MODE,
        )
    else:
        LOG.info("Automated bot disabled; existing bot positions remain managed.")
    return {
        "account_mode": ACCOUNT_MODE,
        "enabled": BOT_ENABLED,
        "score_minimum": BOT_SCALPING_SCORE_MINIMUM,
        "high_confirmation_score_minimum": BOT_SCORE_MINIMUM,
        "scalping_score_maximum": BOT_SCALPING_SCORE_MAXIMUM,
        "scalping_position_count": BOT_SCALPING_POSITION_COUNT,
        "scalping_target_profit_usd": BOT_SCALPING_TARGET_PROFIT_USD,
        "scalping_volume_per_position": BOT_INITIAL_VOLUME,
        "liquidity_sweep_required": True,
        "initial_volume": BOT_INITIAL_VOLUME,
        "addon_volume": BOT_ADDON_VOLUME,
        "risk_percent_maximum": BOT_MAX_RISK_PERCENT,
        "excluded_symbols": ["XAUUSD"],
        "tp_source": "signal_for_9_plus_fixed_usd_for_scalping",
    }


def _bot_setup_comment(analysis: dict[str, object]) -> str | None:
    closed_time = analysis.get("closed_candle_time_utc")
    if not isinstance(closed_time, str):
        return None
    try:
        parsed = datetime.fromisoformat(closed_time.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return None
    return f"ABT{int(parsed.timestamp())}"


def _bot_has_entry_comment(comment: str, magic: int) -> bool:
    end = datetime.now(timezone.utc)
    deals = mt5.history_deals_get(end - timedelta(days=365), end)
    if deals is None:
        raise RuntimeError(
            f"Cannot verify prior bot orders: {mt5.last_error()}"
        )
    entry_types = {mt5.DEAL_ENTRY_IN, mt5.DEAL_ENTRY_INOUT}
    return any(
        deal.magic == magic
        and deal.comment == comment
        and deal.entry in entry_types
        for deal in deals
    )


def _bot_validate_volume(info: Any, volume: float) -> None:
    minimum = float(info.volume_min)
    maximum = float(info.volume_max)
    step = float(info.volume_step)
    if (
        step <= 0
        or volume < minimum
        or volume > maximum
        or abs((volume - minimum) / step - round((volume - minimum) / step)) > 1e-7
    ):
        raise RuntimeError(
            f"The broker does not support the bot's required {volume:.2f}-lot size for {info.name}."
        )


def _bot_place_order(
    *,
    symbol: str,
    direction: str,
    volume: float,
    stop: float,
    target: float,
    target_profit: float | None = None,
    comment: str,
    magic: int,
) -> dict[str, object]:
    account = _require_mt5_trade_permission()
    if account.currency != "USD":
        raise RuntimeError("The bot requires a USD-denominated account.")
    info = _resolve_symbol(symbol)
    _bot_validate_volume(info, volume)
    tick = mt5.symbol_info_tick(info.name)
    if tick is None:
        raise RuntimeError(f"Cannot read the latest quote for {info.name}.")
    tick_age = int(datetime.now(timezone.utc).timestamp()) - (
        int(tick.time) - _server_time_offset(int(tick.time))
    )
    if tick_age < -2 or tick_age > 30:
        raise RuntimeError(f"The latest quote for {info.name} is stale.")

    is_buy = direction == "BUY"
    if direction not in ("BUY", "SELL"):
        raise ValueError("The bot received an invalid trade direction.")
    order_type = mt5.ORDER_TYPE_BUY if is_buy else mt5.ORDER_TYPE_SELL
    entry = float(tick.ask if is_buy else tick.bid)
    if target_profit is not None:
        target = _bot_price_for_target_profit(
            order_type=order_type,
            symbol=info.name,
            volume=volume,
            entry=entry,
            target_profit=target_profit,
            tick_size=float(info.trade_tick_size or info.point),
            digits=int(info.digits),
        )
    minimum_distance = int(info.trade_stops_level) * float(info.point)
    if not all(math.isfinite(value) for value in (entry, stop, target)):
        raise RuntimeError("The bot setup contains an invalid entry, stop, or target.")
    if (
        is_buy
        and not (stop < entry - minimum_distance and target > entry + minimum_distance)
    ) or (
        not is_buy
        and not (stop > entry + minimum_distance and target < entry - minimum_distance)
    ):
        raise RuntimeError("The signal stop or target is invalid for the current broker quote.")

    stop_profit = mt5.order_calc_profit(order_type, info.name, volume, entry, stop)
    if stop_profit is None or not math.isfinite(float(stop_profit)):
        raise RuntimeError(f"Cannot calculate bot order risk: {mt5.last_error()}")
    risk_amount = abs(float(stop_profit))
    balance = float(account.balance)
    if not math.isfinite(balance) or balance <= 0:
        raise RuntimeError("The bot cannot read a valid account balance.")
    maximum_risk = balance * BOT_MAX_RISK_PERCENT / 100
    if risk_amount <= 0 or risk_amount > maximum_risk * 1.001:
        raise RuntimeError(
            f"The required {volume:.2f}-lot order exceeds the {BOT_MAX_RISK_PERCENT:.1f}% per-order risk cap."
        )
    margin = mt5.order_calc_margin(order_type, info.name, volume, entry)
    if margin is None or not math.isfinite(float(margin)) or float(margin) < 0:
        raise RuntimeError(f"Cannot calculate bot order margin: {mt5.last_error()}")
    if float(margin) > float(account.margin_free):
        raise RuntimeError("There is not enough free margin for the bot order.")

    request: dict[str, object] = {
        "action": mt5.TRADE_ACTION_DEAL,
        "symbol": info.name,
        "volume": volume,
        "type": order_type,
        "price": entry,
        "sl": stop,
        "tp": target,
        "deviation": 20,
        "magic": magic,
        "comment": comment[:31],
        "type_time": mt5.ORDER_TIME_GTC,
    }
    check_errors = []
    result = None
    for filling_mode in (mt5.ORDER_FILLING_IOC, mt5.ORDER_FILLING_FOK):
        request["type_filling"] = filling_mode
        check = mt5.order_check(request)
        if check is None or check.retcode != 0:
            check_errors.append(
                check.comment if check is not None else str(mt5.last_error())
            )
            continue
        _require_mt5_trade_permission()
        result = mt5.order_send(request)
        break
    if result is None and check_errors:
        raise RuntimeError(
            "MetaTrader rejected the bot order check: " + "; ".join(check_errors)
        )
    successful_codes = {
        mt5.TRADE_RETCODE_DONE,
        mt5.TRADE_RETCODE_DONE_PARTIAL,
        mt5.TRADE_RETCODE_PLACED,
    }
    if result is None or result.retcode not in successful_codes:
        reason = result.comment if result is not None else mt5.last_error()
        raise RuntimeError(f"MetaTrader did not execute the bot order: {reason}")
    LOG.warning(
        "Bot order: %s %s %.2f lots at %s; stop=%s target=%s order=%s",
        direction,
        info.name,
        volume,
        result.price,
        stop,
        target,
        result.order,
    )
    return {
        "symbol": info.name,
        "volume": volume,
        "price": float(result.price),
        "risk_amount": risk_amount,
        "order": int(result.order),
        "deal": int(result.deal),
    }


def _bot_signal_is_eligible(analysis: dict[str, object]) -> bool:
    return (
        _bot_signal_has_valid_setup(analysis)
        and analysis.get("quality_score", 0) >= BOT_SCORE_MINIMUM
    )


def _bot_signal_is_scalping_eligible(analysis: dict[str, object]) -> bool:
    score = analysis.get("quality_score")
    return (
        _bot_signal_has_valid_setup(analysis)
        and isinstance(score, int)
        and not isinstance(score, bool)
        and BOT_SCALPING_SCORE_MINIMUM <= score <= BOT_SCALPING_SCORE_MAXIMUM
    )


def _bot_signal_has_valid_setup(analysis: dict[str, object]) -> bool:
    criteria = analysis.get("criteria")
    return (
        analysis.get("direction") in ("BUY", "SELL")
        and analysis.get("status") in ("STRONG", "MEDIUM")
        and isinstance(criteria, dict)
        and criteria.get("liquidity_sweep") is True
        and isinstance(analysis.get("stop_loss"), (int, float))
        and isinstance(analysis.get("take_profit"), (int, float))
    )


def _bot_scan_signals() -> None:
    account = _require_mt5_trade_permission()
    positions = mt5.positions_get()
    if positions is None:
        raise RuntimeError(f"Cannot check bot positions: {mt5.last_error()}")

    for symbol in BOT_SYMBOLS:
        try:
            analysis = _read_market(symbol)
            is_scalping = _bot_signal_is_scalping_eligible(analysis)
            if not is_scalping and not _bot_signal_is_eligible(analysis):
                continue
            if (
                is_scalping
                and account.margin_mode != mt5.ACCOUNT_MARGIN_MODE_RETAIL_HEDGING
            ):
                LOG.info(
                    "Bot skipped %s: 7–8 score scalping requires an MT5 hedging account.",
                    symbol,
                )
                continue
            setup_comment = _bot_setup_comment(analysis)
            if setup_comment is None:
                LOG.warning("Bot skipped %s: no valid closed-candle timestamp.", symbol)
                continue
            info = _resolve_symbol(symbol)
            if any(position.symbol == info.name for position in positions):
                continue
            if f"{info.name}:{setup_comment}" in _BOT_SETUP_STATE:
                continue
            entry_magic = (
                BOT_SCALP_ORDER_MAGIC if is_scalping else BOT_ORDER_MAGIC
            )
            if _bot_has_entry_comment(setup_comment, entry_magic):
                continue
            placed_orders = []
            order_count = (
                BOT_SCALPING_POSITION_COUNT if is_scalping else 1
            )
            for _ in range(order_count):
                try:
                    placed_orders.append(
                        _bot_place_order(
                            symbol=symbol,
                            direction=str(analysis["direction"]),
                            volume=BOT_INITIAL_VOLUME,
                            stop=float(analysis["stop_loss"]),
                            target=float(analysis["take_profit"]),
                            target_profit=(
                                BOT_SCALPING_TARGET_PROFIT_USD
                                if is_scalping
                                else None
                            ),
                            comment=setup_comment,
                            magic=entry_magic,
                        )
                    )
                except RuntimeError as error:
                    if not placed_orders:
                        raise
                    LOG.error(
                        "Scalping setup %s on %s placed only %d of %d orders: %s",
                        setup_comment,
                        symbol,
                        len(placed_orders),
                        order_count,
                        error,
                    )
                    break
            _BOT_SETUP_STATE[f"{info.name}:{setup_comment}"] = {
                "initial_stop": float(analysis["stop_loss"]),
                "initial_volume": BOT_INITIAL_VOLUME,
                "scalping": is_scalping,
            }
            if is_scalping and len(placed_orders) < order_count:
                continue
            positions = mt5.positions_get()
            if positions is None:
                raise RuntimeError(
                    f"Cannot refresh bot positions after order: {mt5.last_error()}"
                )
            if is_scalping:
                LOG.info(
                    "Scalping setup %s %s executed: %d orders, %.2f lots and $%.2f target each.",
                    symbol,
                    analysis["direction"],
                    len(placed_orders),
                    BOT_INITIAL_VOLUME,
                    BOT_SCALPING_TARGET_PROFIT_USD,
                )
            else:
                placed = placed_orders[0]
                LOG.info(
                    "High-confirmation setup %s %s executed: %.2f lots, risk %.2f USD.",
                    symbol,
                    analysis["direction"],
                    placed["volume"],
                    placed["risk_amount"],
                )
        except RuntimeError as error:
            LOG.info("Bot skipped %s: %s", symbol, error)


def _bot_load_position_candles(
    info: Any, time_offset: int
) -> list[Candle]:
    rates = mt5.copy_rates_from_pos(
        info.name,
        TIMEFRAMES["15m"][0],
        1,
        MARKET_M15_CANDLE_COUNT,
    )
    if rates is None:
        raise RuntimeError(
            f"Cannot read 15M candles for bot position {info.name}: {mt5.last_error()}"
        )
    return [
        Candle(
            time=int(row["time"]) - time_offset,
            open=float(row["open"]),
            high=float(row["high"]),
            low=float(row["low"]),
            close=float(row["close"]),
        )
        for row in rates
    ]


def _bot_impulse_date(
    candles: list[Candle], opened_at: int, direction: str
) -> datetime.date | None:
    impulse_dates = []
    for index, candle in enumerate(candles):
        if candle.time <= opened_at or index < 14:
            continue
        atr = _atr(candles[index - 14 : index + 1])
        body = candle.close - candle.open
        if atr > 0 and (
            body >= 1.5 * atr if direction == "BUY" else -body >= 1.5 * atr
        ):
            impulse_dates.append(
                datetime.fromtimestamp(candle.time, timezone.utc).date()
            )
    return max(impulse_dates) if impulse_dates else None


def _bot_close_position(position: Any, tick: Any) -> None:
    is_buy = position.type == mt5.POSITION_TYPE_BUY
    request: dict[str, object] = {
        "action": mt5.TRADE_ACTION_DEAL,
        "position": int(position.ticket),
        "symbol": position.symbol,
        "volume": float(position.volume),
        "type": mt5.ORDER_TYPE_SELL if is_buy else mt5.ORDER_TYPE_BUY,
        "price": float(tick.bid if is_buy else tick.ask),
        "deviation": 20,
        "magic": int(position.magic),
        "comment": "ARTBOT day end",
        "type_time": mt5.ORDER_TIME_GTC,
    }
    errors = []
    result = None
    for filling_mode in (mt5.ORDER_FILLING_IOC, mt5.ORDER_FILLING_FOK):
        request["type_filling"] = filling_mode
        check = mt5.order_check(request)
        if check is None or check.retcode != 0:
            errors.append(check.comment if check is not None else str(mt5.last_error()))
            continue
        _require_mt5_trade_permission()
        result = mt5.order_send(request)
        break
    if result is None or result.retcode not in {
        mt5.TRADE_RETCODE_DONE,
        mt5.TRADE_RETCODE_DONE_PARTIAL,
        mt5.TRADE_RETCODE_PLACED,
    }:
        reason = (
            "; ".join(errors)
            if result is None
            else result.comment
        )
        raise RuntimeError(f"Could not close the bot position at UTC day end: {reason}")
    LOG.warning(
        "Bot closed position %s %s at UTC day end.",
        position.symbol,
        position.ticket,
    )


def _bot_price_for_profit(
    order_type: int,
    symbol: str,
    volume: float,
    opened_at: float,
    current_price: float,
    locked_profit: float,
) -> float | None:
    if order_type == mt5.ORDER_TYPE_BUY:
        if current_price <= opened_at:
            return None
        low, high = opened_at, current_price
        for _ in range(48):
            middle = (low + high) / 2
            profit = mt5.order_calc_profit(
                order_type, symbol, volume, opened_at, middle
            )
            if profit is None:
                raise RuntimeError(
                    f"Cannot calculate trailing-stop profit: {mt5.last_error()}"
                )
            if float(profit) >= locked_profit:
                high = middle
            else:
                low = middle
        return high
    if current_price >= opened_at:
        return None
    low, high = current_price, opened_at
    for _ in range(48):
        middle = (low + high) / 2
        profit = mt5.order_calc_profit(
            order_type, symbol, volume, opened_at, middle
        )
        if profit is None:
            raise RuntimeError(
                f"Cannot calculate trailing-stop profit: {mt5.last_error()}"
            )
        if float(profit) >= locked_profit:
            low = middle
        else:
            high = middle
    return low


def _bot_price_for_target_profit(
    *,
    order_type: int,
    symbol: str,
    volume: float,
    entry: float,
    target_profit: float,
    tick_size: float,
    digits: int,
) -> float:
    if order_type not in (mt5.ORDER_TYPE_BUY, mt5.ORDER_TYPE_SELL):
        raise ValueError("The bot received an invalid order type for its target.")
    if not all(
        math.isfinite(value)
        for value in (volume, entry, target_profit, tick_size)
    ) or volume <= 0 or entry <= 0 or target_profit <= 0 or tick_size <= 0:
        raise RuntimeError("The bot scalping target contains an invalid value.")
    direction = 1 if order_type == mt5.ORDER_TYPE_BUY else -1
    profit_tolerance = max(1e-8, target_profit * 1e-10)

    def profit_at_distance(distance: float) -> float:
        close = entry + direction * distance
        if close <= 0:
            raise RuntimeError("Cannot calculate a valid scalping target price.")
        profit = mt5.order_calc_profit(order_type, symbol, volume, entry, close)
        if profit is None or not math.isfinite(float(profit)):
            raise RuntimeError(
                f"Cannot calculate the bot scalping target: {mt5.last_error()}"
            )
        return float(profit)

    low = 0.0
    high = tick_size
    for _ in range(64):
        if profit_at_distance(high) >= target_profit - profit_tolerance:
            break
        high *= 2
    else:
        raise RuntimeError("Cannot find a price for the bot scalping target.")

    for _ in range(48):
        middle = (low + high) / 2
        if profit_at_distance(middle) >= target_profit - profit_tolerance:
            high = middle
        else:
            low = middle

    raw_target = entry + direction * high
    tick_units = raw_target / tick_size
    aligned_target = (
        math.ceil(tick_units - 1e-10) * tick_size
        if direction > 0
        else math.floor(tick_units + 1e-10) * tick_size
    )
    target = round(aligned_target, digits)
    for _ in range(4):
        profit = mt5.order_calc_profit(order_type, symbol, volume, entry, target)
        if profit is None or not math.isfinite(float(profit)):
            raise RuntimeError(
                f"Cannot verify the bot scalping target: {mt5.last_error()}"
            )
        if float(profit) >= target_profit - profit_tolerance:
            return target
        target = round(target + direction * tick_size, digits)
    raise RuntimeError("The broker tick size prevents reaching the $4 scalping target.")


def _bot_addon_is_ready(
    direction: str,
    opened_at: float,
    initial_risk: float,
    current_price: float,
    favorable_extreme: float,
    atr: float,
) -> bool:
    if initial_risk <= 0 or atr <= 0:
        return False
    progress = (
        current_price - opened_at
        if direction == "BUY"
        else opened_at - current_price
    )
    pullback = (
        favorable_extreme - current_price
        if direction == "BUY"
        else current_price - favorable_extreme
    )
    return progress >= initial_risk and 0 <= pullback <= 0.5 * atr


def _bot_adjust_position_stop(position: Any, info: Any, tick: Any) -> None:
    if float(position.profit) < 1:
        return
    locked_profit = min(5, math.floor(float(position.profit)))
    if locked_profit < 1:
        return
    is_buy = position.type == mt5.POSITION_TYPE_BUY
    order_type = mt5.ORDER_TYPE_BUY if is_buy else mt5.ORDER_TYPE_SELL
    current_price = float(tick.bid if is_buy else tick.ask)
    candidate = _bot_price_for_profit(
        order_type,
        info.name,
        float(position.volume),
        float(position.price_open),
        current_price,
        float(locked_profit),
    )
    if candidate is None:
        return
    tick_size = float(info.trade_tick_size or info.point)
    if tick_size <= 0:
        raise RuntimeError(f"Invalid tick size for bot position {info.name}.")
    candidate = (
        math.ceil(candidate / tick_size) * tick_size
        if is_buy
        else math.floor(candidate / tick_size) * tick_size
    )
    candidate = round(candidate, int(info.digits))
    old_stop = float(position.sl)
    if is_buy and old_stop > 0 and candidate <= old_stop:
        return
    if not is_buy and old_stop > 0 and candidate >= old_stop:
        return
    min_distance = max(
        int(info.trade_stops_level),
        int(getattr(info, "trade_freeze_level", 0)),
    ) * float(info.point)
    if (
        is_buy and candidate >= float(tick.bid) - min_distance
    ) or (
        not is_buy and candidate <= float(tick.ask) + min_distance
    ):
        return
    request = {
        "action": mt5.TRADE_ACTION_SLTP,
        "position": int(position.ticket),
        "symbol": position.symbol,
        "sl": candidate,
        "tp": float(position.tp),
    }
    result = mt5.order_send(request)
    if result is None or result.retcode != mt5.TRADE_RETCODE_DONE:
        reason = result.comment if result is not None else mt5.last_error()
        raise RuntimeError(
            f"Could not ratchet bot stop for {position.symbol}: {reason}"
        )
    LOG.info(
        "Bot stop moved for %s position %s to lock approximately %d USD.",
        position.symbol,
        position.ticket,
        locked_profit,
    )


def _bot_try_addon(
    position: Any,
    analysis: dict[str, object],
    info: Any,
    tick: Any,
    candles: list[Candle],
    time_offset: int,
) -> None:
    if position.magic != BOT_ORDER_MAGIC or not _bot_signal_is_eligible(analysis):
        return
    setup_comment = str(position.comment or "")
    if not setup_comment.startswith("ABT"):
        candidates = [
            key.split(":", 1)[1]
            for key in _BOT_SETUP_STATE
            if key.startswith(f"{info.name}:")
        ]
        if not candidates:
            return
        setup_comment = candidates[-1]
    state = _BOT_SETUP_STATE.get(f"{info.name}:{setup_comment}", {})
    if state.get("addon_order") is not None:
        return
    if _bot_has_entry_comment(f"ABA{setup_comment[3:]}", BOT_ADDON_ORDER_MAGIC):
        return
    if analysis.get("direction") != (
        "BUY" if position.type == mt5.POSITION_TYPE_BUY else "SELL"
    ):
        return
    initial_stop = state.get("initial_stop")
    if not isinstance(initial_stop, (int, float)):
        initial_stop = float(position.sl)
    initial_risk = abs(float(position.price_open) - float(initial_stop))
    if initial_risk <= 0:
        return
    opened_at = int(position.time) - time_offset
    since_open = [candle for candle in candles if candle.time >= opened_at]
    atr = _atr(candles)
    if atr <= 0 or not since_open:
        return
    is_buy = position.type == mt5.POSITION_TYPE_BUY
    current_price = float(tick.bid if is_buy else tick.ask)
    favorable_extreme = (
        max(current_price, *(candle.high for candle in since_open))
        if is_buy
        else min(current_price, *(candle.low for candle in since_open))
    )
    if not _bot_addon_is_ready(
        "BUY" if is_buy else "SELL",
        float(position.price_open),
        initial_risk,
        current_price,
        favorable_extreme,
        atr,
    ):
        return
    stop = float(analysis["stop_loss"])
    if float(position.sl) > 0:
        stop = max(stop, float(position.sl)) if is_buy else min(
            stop, float(position.sl)
        )
    target = float(position.tp or analysis["take_profit"])
    comment = f"ABA{setup_comment[3:]}"
    placed = _bot_place_order(
        symbol=info.name,
        direction="BUY" if is_buy else "SELL",
        volume=BOT_ADDON_VOLUME,
        stop=stop,
        target=target,
        comment=comment,
        magic=BOT_ADDON_ORDER_MAGIC,
    )
    _BOT_SETUP_STATE.setdefault(
        f"{info.name}:{setup_comment}",
        {"initial_stop": float(initial_stop), "initial_volume": BOT_INITIAL_VOLUME},
    )["addon_order"] = placed["order"]
    LOG.info(
        "Bot 0.01-lot add-on executed for %s after at least 1R progress and a bounded pullback.",
        info.name,
    )


def _bot_manage_positions() -> None:
    positions = mt5.positions_get()
    if positions is None:
        raise RuntimeError(f"Cannot read open positions for bot management: {mt5.last_error()}")
    bot_positions = [
        position
        for position in positions
        if position.magic
        in (BOT_ORDER_MAGIC, BOT_ADDON_ORDER_MAGIC, BOT_SCALP_ORDER_MAGIC)
    ]
    if not bot_positions:
        return
    account = _require_active_account()
    if account.currency != "USD":
        LOG.error("Bot position management is paused because the account is not USD-denominated.")
        return
    terminal = mt5.terminal_info()
    if terminal is None or not terminal.trade_allowed or not account.trade_allowed:
        LOG.warning("Bot position management is paused because MT5 trading is disabled.")
        return

    cached: dict[str, tuple[dict[str, object], Any, Any, list[Candle], int]] = {}
    now = datetime.now(timezone.utc)
    for position in bot_positions:
        base_name = next(
            (symbol for symbol in BOT_SYMBOLS if position.symbol.startswith(symbol)),
            None,
        )
        if base_name is None:
            continue
        try:
            if position.symbol not in cached:
                analysis = _read_market(base_name)
                info = _resolve_symbol(base_name)
                tick = mt5.symbol_info_tick(info.name)
                if tick is None:
                    raise RuntimeError(f"No current quote for {info.name}.")
                offset = _server_time_offset(int(tick.time))
                candles = _bot_load_position_candles(info, offset)
                cached[position.symbol] = (analysis, info, tick, candles, offset)
            analysis, info, tick, candles, offset = cached[position.symbol]
            _bot_adjust_position_stop(position, info, tick)
            direction = (
                "BUY" if position.type == mt5.POSITION_TYPE_BUY else "SELL"
            )
            opened_at = int(position.time) - offset
            impulse_date = _bot_impulse_date(candles, opened_at, direction)
            if impulse_date is not None:
                end_of_day = datetime(
                    impulse_date.year,
                    impulse_date.month,
                    impulse_date.day,
                    23,
                    59,
                    tzinfo=timezone.utc,
                )
                if now >= end_of_day:
                    _bot_close_position(position, tick)
                    continue
            if BOT_ENABLED:
                current_positions = mt5.positions_get()
                if current_positions is None:
                    raise RuntimeError(
                        f"Cannot refresh bot positions: {mt5.last_error()}"
                    )
                current_position = next(
                    (
                        item
                        for item in current_positions
                        if item.ticket == position.ticket
                    ),
                    position,
                )
                symbol_positions = [
                    item
                    for item in current_positions
                    if item.symbol == position.symbol
                ]
                if any(
                    item.magic not in (BOT_ORDER_MAGIC, BOT_ADDON_ORDER_MAGIC)
                    for item in symbol_positions
                ) or len(symbol_positions) > 2:
                    continue
                _bot_try_addon(
                    current_position, analysis, info, tick, candles, offset
                )
        except RuntimeError as error:
            LOG.warning(
                "Bot could not manage %s position %s: %s",
                position.symbol,
                position.ticket,
                error,
            )


def _bot_worker() -> None:
    while not _BOT_STOP.is_set():
        try:
            with _ORDER_EXECUTION_LOCK:
                _bot_manage_positions()
                if BOT_ENABLED:
                    _bot_scan_signals()
        except RuntimeError as error:
            LOG.warning("Bot cycle paused: %s", error)
        except Exception:
            LOG.exception("Unexpected bot cycle failure.")
        _BOT_STOP.wait(BOT_SCAN_INTERVAL_SECONDS)


def _server_time_offset(
    timestamp: int, *, local_now: datetime | None = None
) -> int:
    """Correct a near-current broker wall clock encoded as UTC."""
    local_now = local_now or datetime.now().astimezone()
    now_utc = local_now.astimezone(timezone.utc)
    future_difference = timestamp - int(now_utc.timestamp())
    broker_offset = round(future_difference / 3600) * 3600
    if (
        0 < broker_offset <= 14 * 3600
        and abs(future_difference - broker_offset) <= 120
    ):
        return broker_offset
    return 0


def _read_market(base_name: str) -> dict[str, object]:
    _require_active_account()
    info = _resolve_symbol(base_name)
    tick = mt5.symbol_info_tick(info.name)
    if tick is None or tick.time <= 0:
        raise RuntimeError(f"No broker quote is available for {info.name}.")
    time_offset = _server_time_offset(int(tick.time))
    quote = MarketQuote(
        bid=float(tick.bid),
        ask=float(tick.ask),
        time=int(tick.time) - time_offset,
        digits=int(info.digits),
        point=float(info.point),
    )
    candles: dict[str, list[Candle]] = {}
    for timeframe, (mt5_timeframe, count) in TIMEFRAMES.items():
        is_position_chart = base_name in POSITION_CHART_SYMBOLS and timeframe == "5m"
        if timeframe not in ("4h", "1h", "15m") and not is_position_chart:
            continue
        if timeframe == "15m":
            count = MARKET_M15_CANDLE_COUNT
        rates = mt5.copy_rates_from_pos(info.name, mt5_timeframe, 1, count)
        if rates is None:
            raise RuntimeError(
                f"Cannot read {timeframe} candles for {info.name}: {mt5.last_error()}"
            )
        candles[timeframe] = [
            Candle(
                time=int(row["time"]) - time_offset,
                open=float(row["open"]),
                high=float(row["high"]),
                low=float(row["low"]),
                close=float(row["close"]),
            )
            for row in rates
        ]
    result = analyze_market(
        base_name,
        quote,
        candles["4h"],
        candles["1h"],
        m15=candles["15m"],
    )
    candle_history = result.get("candle_history")
    if isinstance(candle_history, dict) and base_name in POSITION_CHART_SYMBOLS:
        candle_history["15m"] = _serialize_chart_candles(candles["15m"])
        candle_history["5m"] = _serialize_chart_candles(candles["5m"])
    return result

def _serialize_chart_candles(candles: list[Candle]) -> list[dict[str, object]]:
    return [
        {
            "time_utc": datetime.fromtimestamp(candle.time, timezone.utc).isoformat(),
            "open": candle.open,
            "high": candle.high,
            "low": candle.low,
            "close": candle.close,
        }
        for candle in candles
    ]


def _response(*, include_market: bool) -> dict[str, object]:
    _require_active_account()
    generated = datetime.now(timezone.utc).isoformat()
    result: dict[str, object] = {
        "source": f"MT5 {ACCOUNT_MODE} account · closed-candle analysis",
        "generated_at_utc": generated,
        "account_connected": True,
        "read_only": True,
        "trading_enabled": TRADE_TOKEN is not None,
        "account_mode": ACCOUNT_MODE,
    }
    if include_market:
        markets = []
        errors = []
        for symbol in SYMBOLS:
            try:
                markets.append(
                    _read_market(symbol)
                )
            except RuntimeError as error:
                LOG.warning("%s market read failed: %s", symbol, error)
                errors.append(f"{symbol}: {error}")
        if not markets:
            raise RuntimeError(
                "No market quotes could be read. " + "; ".join(errors)
            )
        result["markets"] = markets
        result["market_errors"] = errors
    return result


class MarketFeedHandler(BaseHTTPRequestHandler):
    server_version = "AurumTradingFeed/1.0"

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self._cors_headers()
        self.end_headers()

    def do_GET(self) -> None:
        if self.path == "/api/account":
            if not self._authorized():
                self._send_json(403, {"error": "Account access is not authorized."})
                return
            try:
                self._send_json(200, _account_summary())
            except RuntimeError as error:
                self._send_json(503, {"error": str(error)})
            return
        if self.path == "/api/history":
            if not self._authorized():
                self._send_json(403, {"error": "History access is not authorized."})
                return
            try:
                self._send_json(200, _trade_history())
            except RuntimeError as error:
                self._send_json(503, {"error": str(error)})
            return
        routes = {"/health": False, "/api/market/signals": True}
        include_market = routes.get(self.path)
        if include_market is None:
            self._send_json(404, {"error": "Endpoint not found."})
            return
        try:
            self._send_json(200, _response(include_market=include_market))
        except RuntimeError as error:
            LOG.warning("Market feed unavailable: %s", error)
            self._send_json(503, {"error": str(error)})
        except Exception:
            LOG.exception("Unexpected market feed failure")
            self._send_json(
                500,
                {"error": "Unexpected market-feed error; see local service log."},
            )

    def do_POST(self) -> None:
        supported_routes = {
            "/api/account/connect",
            "/api/order-review/config",
            "/api/bot/config",
            "/api/order/preview",
            "/api/order/execute",
        }
        if self.path not in supported_routes:
            self._send_json(404, {"error": "Endpoint not found."})
            return
        if not self._authorized():
            self._send_json(403, {"error": "Trading is not authorized for this session."})
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 4096:
                raise ValueError("Request body is missing or too large.")
            payload = json.loads(self.rfile.read(length))
            if not isinstance(payload, dict):
                raise ValueError("Request body must be a JSON object.")
            if self.path == "/api/account/connect":
                response = _connect_account(payload)
            elif self.path == "/api/order-review/config":
                response = _configure_order_review(payload)
            elif self.path == "/api/bot/config":
                response = _configure_bot(payload)
            elif self.path.endswith("/preview"):
                response = _make_order_preview(payload)
            else:
                response = _execute_demo_order(payload)
            self._send_json(200, response)
        except (ValueError, RuntimeError, json.JSONDecodeError) as error:
            self._send_json(400, {"error": str(error)})
        except Exception:
            LOG.exception("Unexpected order failure")
            self._send_json(
                500,
                {"error": "Unexpected trading error; see local service log."},
            )

    def _authorized(self) -> bool:
        if not TRADE_TOKEN:
            return False
        authorization = self.headers.get("Authorization", "")
        if not authorization.startswith("Bearer "):
            return False
        provided = authorization.removeprefix("Bearer ").strip()
        return hmac.compare_digest(provided, TRADE_TOKEN)

    def _send_json(self, status: int, body: dict[str, object]) -> None:
        encoded = json.dumps(body, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self._cors_headers()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def _cors_headers(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.send_header("Access-Control-Max-Age", "600")

    def log_message(self, format: str, *args: object) -> None:
        LOG.info("%s - %s", self.address_string(), format % args)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Serve local MetaTrader quotes, account data, and authorized trading."
    )
    parser.add_argument(
        "--host",
        default="127.0.0.1",
        help="Bind address; loopback only is recommended (default: 127.0.0.1).",
    )
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        stream=sys.stdout,
    )
    if ACCOUNT_MODE not in ("demo", "live"):
        raise SystemExit("AURUM_ACCOUNT_MODE must be either 'demo' or 'live'.")
    if not mt5.initialize(TERMINAL_PATH, timeout=10_000):
        raise SystemExit(
            "Could not attach to the configured MetaTrader 5 terminal: "
            f"{mt5.last_error()}. Open and sign in to the selected account, then "
            "restart this feed."
        )
    try:
        service = ThreadingHTTPServer((args.host, args.port), MarketFeedHandler)
    except Exception:
        mt5.shutdown()
        raise

    account = mt5.account_info()
    LOG.info(
        "MetaTrader %s feed listening at http://%s:%d "
        "(account %s; trading API %s).",
        ACCOUNT_MODE,
        args.host,
        args.port,
        (
            f"{int(account.login)} on {account.server}"
            if account is not None
            else "not signed in"
        ),
        "authorized for this app session" if TRADE_TOKEN else "disabled",
    )
    worker = None
    if TRADE_TOKEN:
        _BOT_STOP.clear()
        worker = threading.Thread(
            target=_bot_worker,
            name="mt5-high-confirmation-bot",
            daemon=True,
        )
        worker.start()
    try:
        service.serve_forever()
    except KeyboardInterrupt:
        LOG.info("Stopping local market feed.")
    finally:
        _BOT_STOP.set()
        if worker is not None:
            worker.join(timeout=BOT_SCAN_INTERVAL_SECONDS + 1)
        service.server_close()
        mt5.shutdown()


if __name__ == "__main__":
    main()
