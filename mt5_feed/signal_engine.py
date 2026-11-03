"""Rule-based market analysis from closed MetaTrader candles."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Literal, Sequence


Direction = Literal["BUY", "SELL", "RANGE"]


@dataclass(frozen=True)
class Candle:
    time: int
    open: float
    high: float
    low: float
    close: float


@dataclass(frozen=True)
class MarketQuote:
    bid: float
    ask: float
    time: int
    digits: int
    point: float


@dataclass(frozen=True)
class Swing:
    index: int
    price: float


def _swing_points(
    candles: Sequence[Candle], direction: Literal["high", "low"], wing: int = 2
) -> list[Swing]:
    values: list[Swing] = []
    for index in range(wing, len(candles) - wing):
        price = candles[index].high if direction == "high" else candles[index].low
        before = [
            candle.high if direction == "high" else candle.low
            for candle in candles[index - wing : index]
        ]
        after = [
            candle.high if direction == "high" else candle.low
            for candle in candles[index + 1 : index + wing + 1]
        ]
        if direction == "high":
            is_pivot = price >= max(before) and price > max(after)
        else:
            is_pivot = price <= min(before) and price < min(after)
        if is_pivot:
            values.append(Swing(index=index, price=price))
    return values


def _structure_bias(candles: Sequence[Candle]) -> Direction:
    highs = _swing_points(candles, "high")
    lows = _swing_points(candles, "low")
    if len(highs) < 2 or len(lows) < 2:
        return "RANGE"
    higher_highs = highs[-1].price > highs[-2].price
    higher_lows = lows[-1].price > lows[-2].price
    lower_highs = highs[-1].price < highs[-2].price
    lower_lows = lows[-1].price < lows[-2].price
    if higher_highs and higher_lows:
        return "BUY"
    if lower_highs and lower_lows:
        return "SELL"
    return "RANGE"


def _atr(candles: Sequence[Candle], period: int = 14) -> float:
    recent = candles[-(period + 1) :]
    true_ranges: list[float] = []
    for previous, current in zip(recent, recent[1:]):
        true_ranges.append(
            max(
                current.high - current.low,
                abs(current.high - previous.close),
                abs(current.low - previous.close),
            )
        )
    return sum(true_ranges) / len(true_ranges) if true_ranges else 0.0


def _liquidity_sweep(
    candles: Sequence[Candle],
) -> tuple[Direction | None, int | None, float | None]:
    if len(candles) < 25:
        return None, None, None

    first_candidate = max(20, len(candles) - 5)
    for index in range(len(candles) - 2, first_candidate - 1, -1):
        candle = candles[index]
        reference = candles[max(0, index - 20) : index]
        displacement = _atr(candles[max(0, index - 14) : index + 1])
        if not reference or displacement <= 0:
            continue
        prior_low = min(item.low for item in reference)
        prior_high = max(item.high for item in reference)
        bullish = (
            candle.low < prior_low
            and candle.close > prior_low
            and candle.close > candle.open
            and candle.close - candle.open >= displacement * 0.8
        )
        bearish = (
            candle.high > prior_high
            and candle.close < prior_high
            and candle.close < candle.open
            and candle.open - candle.close >= displacement * 0.8
        )
        if bullish:
            return "BUY", index, prior_low
        if bearish:
            return "SELL", index, prior_high
    return None, None, None


def _structure_shift_index(
    candles: Sequence[Candle], direction: Direction, sweep_index: int | None
) -> int | None:
    if direction == "RANGE" or sweep_index is None or sweep_index >= len(candles) - 1:
        return None
    reference = candles[max(0, sweep_index - 5) : sweep_index]
    after_sweep = candles[sweep_index + 1 :]
    if not reference or not after_sweep:
        return None
    if direction == "BUY":
        level = max(candle.high for candle in reference)
        return next(
            (
                index
                for index in range(sweep_index + 1, len(candles))
                if candles[index].close > level
            ),
            None,
        )
    level = min(candle.low for candle in reference)
    return next(
        (
            index
            for index in range(sweep_index + 1, len(candles))
            if candles[index].close < level
        ),
        None,
    )


def _mitigated_imbalance(
    candles: Sequence[Candle], direction: Direction, price: float
) -> bool:
    if direction == "RANGE" or len(candles) < 3:
        return False
    for index in range(max(0, len(candles) - 12), len(candles) - 2):
        left, middle, right = candles[index : index + 3]
        if direction == "BUY" and left.high < right.low:
            if left.high <= price <= right.low and middle.close > middle.open:
                return True
        elif direction == "SELL" and left.low > right.high:
            if right.high <= price <= left.low and middle.close < middle.open:
                return True
    return False


def _mitigated_order_block(
    candles: Sequence[Candle], direction: Direction, price: float
) -> tuple[bool, float | None]:
    if direction == "RANGE":
        return False, None
    for candle in reversed(candles[-12:-1]):
        opposite_candle = (
            candle.close < candle.open
            if direction == "BUY"
            else candle.close > candle.open
        )
        if opposite_candle and candle.low <= price <= candle.high:
            return True, candle.low if direction == "BUY" else candle.high
    return False, None


def _latest_fvg(
    candles: Sequence[Candle], direction: Direction
) -> tuple[int, float, float] | None:
    if direction == "RANGE":
        return None
    for index in range(len(candles) - 3, max(-1, len(candles) - 13), -1):
        left, middle, right = candles[index : index + 3]
        if direction == "BUY" and left.high < right.low and middle.close > middle.open:
            low, high = left.high, right.low
            if not any(
                candle.low <= high and candle.high >= low
                for candle in candles[index + 3 :]
            ):
                return index, low, high
        if direction == "SELL" and left.low > right.high and middle.close < middle.open:
            low, high = right.high, left.low
            if not any(
                candle.low <= high and candle.high >= low
                for candle in candles[index + 3 :]
            ):
                return index, low, high
    return None


def _latest_order_block(
    candles: Sequence[Candle], direction: Direction
) -> tuple[int, float, float] | None:
    if direction == "RANGE":
        return None
    for index in range(len(candles) - 2, max(-1, len(candles) - 13), -1):
        candle = candles[index]
        is_opposite = (
            candle.close < candle.open
            if direction == "BUY"
            else candle.close > candle.open
        )
        if is_opposite and not any(
            later.low <= candle.high and later.high >= candle.low
            for later in candles[index + 1 :]
        ):
            return index, candle.low, candle.high
    return None


def _structure_retest(
    candles: Sequence[Candle],
    direction: Direction,
    sweep_index: int | None,
) -> tuple[int, float] | None:
    if direction == "RANGE" or sweep_index is None:
        return None
    reference = candles[max(0, sweep_index - 5) : sweep_index]
    if not reference:
        return None
    level = (
        max(candle.high for candle in reference)
        if direction == "BUY"
        else min(candle.low for candle in reference)
    )
    breakout_indices = [
        index
        for index in range(sweep_index + 1, len(candles))
        if (
            candles[index].close > level
            if direction == "BUY"
            else candles[index].close < level
        )
    ]
    if not breakout_indices:
        return None
    breakout_index = breakout_indices[0]
    for index in range(breakout_index + 1, len(candles)):
        candle = candles[index]
        touched_level = candle.low <= level <= candle.high
        held_after_retest = (
            candle.close > level
            if direction == "BUY"
            else candle.close < level
        )
        if touched_level and held_after_retest:
            return index, level
    return None


def _chart_patterns(
    frames: dict[str, Sequence[Candle]],
    *,
    price: float,
    h4_bias: Direction,
) -> list[dict[str, object]]:
    patterns: list[dict[str, object]] = []
    for timeframe, candles in frames.items():
        if len(candles) < 25:
            continue
        sweep_direction, sweep_index, sweep_level = _liquidity_sweep(candles)
        if (
            sweep_direction is None
            or sweep_index is None
            or sweep_level is None
            or h4_bias != sweep_direction
            or len(candles) - 1 - sweep_index > 10
        ):
            continue
        shift_index = _structure_shift_index(
            candles, sweep_direction, sweep_index
        )
        if shift_index is None:
            continue
        post_shift = candles[shift_index:]
        atr = _atr(candles)
        if atr <= 0:
            continue
        zones = [
            ("fvg", _latest_fvg(post_shift, sweep_direction)),
            ("order_block", _latest_order_block(post_shift, sweep_direction)),
        ]
        qualifying_zones: list[tuple[str, int, float, float, float, int]] = []
        for kind, zone in zones:
            if zone is None:
                continue
            shifted_index, low, high = zone
            index = shifted_index + shift_index
            entry = (low + high) / 2
            is_ahead = high < price if sweep_direction == "BUY" else low > price
            distance = abs(price - entry)
            if not is_ahead or distance > atr * 3:
                continue
            points = 25 + 25 + 25 + 12
            if points < 80:
                continue
            qualifying_zones.append((kind, index, low, high, entry, points))

        if not qualifying_zones:
            continue

        end_time = datetime.fromtimestamp(candles[-1].time, timezone.utc).isoformat()
        sweep_candle = candles[sweep_index]
        sweep_time = datetime.fromtimestamp(
            sweep_candle.time, timezone.utc
        ).isoformat()
        patterns.append(
            {
                "type": "liquidity_sweep",
                "timeframe": timeframe,
                "direction": sweep_direction,
                "start_time_utc": sweep_time,
                "end_time_utc": end_time,
                "low": sweep_level,
                "high": sweep_level,
                "level": sweep_level,
                "confluence_score": 87,
                "entry": None,
            }
        )
        retest = _structure_retest(candles, sweep_direction, sweep_index)
        if retest is not None:
            index, level = retest
            retest_time = datetime.fromtimestamp(
                candles[index].time, timezone.utc
            ).isoformat()
            patterns.append(
                {
                    "type": "retest",
                    "timeframe": timeframe,
                    "direction": sweep_direction,
                    "start_time_utc": retest_time,
                    "end_time_utc": end_time,
                    "low": level,
                    "high": level,
                    "level": level,
                    "confluence_score": 87,
                    "entry": None,
                }
            )
        for kind, index, low, high, entry, score in qualifying_zones:
            start_index = index + 2 if kind == "fvg" else index
            patterns.append(
                {
                    "type": kind,
                    "timeframe": timeframe,
                    "direction": sweep_direction,
                    "start_time_utc": datetime.fromtimestamp(
                        candles[start_index].time, timezone.utc
                    ).isoformat(),
                    "end_time_utc": end_time,
                    "low": low,
                    "high": high,
                    "level": None,
                    "confluence_score": score,
                    "entry": entry,
                }
            )
            patterns.append(
                {
                    "type": "entry",
                    "timeframe": timeframe,
                    "direction": sweep_direction,
                    "start_time_utc": end_time,
                    "end_time_utc": end_time,
                    "low": entry,
                    "high": entry,
                    "level": entry,
                    "confluence_score": score,
                    "entry": entry,
                }
            )
    return patterns


def _score(criteria: dict[str, bool]) -> int:
    weights = {
        "h4_trend_alignment": 2,
        "h1_structure_alignment": 2,
        "liquidity_identified": 2,
        "liquidity_sweep": 2,
        "structure_shift": 2,
        "displacement": 1,
        "entry_zone": 1,
        "risk_reward": 1,
    }
    return sum(weight for name, weight in weights.items() if criteria[name])


def analyze_market(
    symbol: str,
    quote: MarketQuote,
    h4: Sequence[Candle],
    h1: Sequence[Candle],
    *,
    m15: Sequence[Candle] = (),
    now: datetime | None = None,
    max_quote_age_seconds: int = 30,
) -> dict[str, object]:
    current_time = now or datetime.now(timezone.utc)
    age_seconds = int(current_time.timestamp()) - quote.time
    quote_is_fresh = -2 <= age_seconds <= max_quote_age_seconds
    reported_quote_age = max(age_seconds, 0)
    price = (quote.bid + quote.ask) / 2
    spread = quote.ask - quote.bid
    pip = quote.point * (10 if quote.digits in (3, 5) else 1)
    stale_reason = "Quote is stale; waiting for a fresh broker tick."
    insufficient_reason = "Insufficient closed candles for multi-timeframe analysis."

    result: dict[str, object] = {
        "symbol": symbol,
        "direction": "WAIT",
        "status": "STALE" if not quote_is_fresh else "WAIT",
        "quality_score": 0,
        "quality_score_max": 13,
        "bid": quote.bid,
        "ask": quote.ask,
        "spread_pips": round(spread / pip, 2) if pip > 0 else None,
        "quote_time_utc": datetime.fromtimestamp(
            quote.time, timezone.utc
        ).isoformat(),
        "quote_age_seconds": reported_quote_age,
        "closed_candle_time_utc": (
            datetime.fromtimestamp(m15[-1].time, timezone.utc).isoformat()
            if m15
            else datetime.fromtimestamp(h1[-1].time, timezone.utc).isoformat()
            if h1
            else None
        ),
        "timeframes": {"4h": "RANGE", "1h": "RANGE", "15m": "WAIT"},
        "criteria": {
            "h4_structure": False,
            "h1_structure": False,
            "liquidity_identified": False,
            "liquidity_sweep": False,
            "structure_shift": False,
            "displacement": False,
            "entry_zone": False,
            "order_block": False,
            "fvg": False,
            "risk_reward": False,
        },
        "chart_patterns": [],
        "entry": None,
        "stop_loss": None,
        "take_profit": None,
        "risk_reward": None,
        "reason": stale_reason if not quote_is_fresh else insufficient_reason,
        "candle_history": {
            "4h": _serialize_candles(h4[-80:]),
            "1h": _serialize_candles(h1[-80:]),
            "15m": _serialize_candles(m15[-80:]),
        },
    }
    if not quote_is_fresh or min(len(h4), len(h1)) < 25:
        return result
    if len(m15) < 25:
        result["reason"] = (
            f"Insufficient closed 15M candles for entry analysis "
            f"({len(m15)}/25 required)."
        )
        return result

    h4_bias = _structure_bias(h4)
    h1_bias = _structure_bias(h1)
    m15_bias = _structure_bias(m15) if len(m15) >= 25 else "RANGE"
    h1_sweep_direction, h1_sweep_index, _ = _liquidity_sweep(h1)
    m15_sweep_direction, m15_sweep_index, _ = _liquidity_sweep(m15)
    direction: Direction = (
        h4_bias
        if h4_bias in ("BUY", "SELL")
        else h1_bias
        if h1_bias in ("BUY", "SELL")
        else m15_sweep_direction
        if m15_sweep_direction in ("BUY", "SELL")
        else m15_bias
    )
    if direction == "RANGE" and h1_sweep_direction in ("BUY", "SELL"):
        direction = h1_sweep_direction

    sweep_candidates: list[tuple[int, Sequence[Candle], int]] = []
    if m15_sweep_direction == direction and m15_sweep_index is not None:
        sweep_candidates.append((m15[m15_sweep_index].time, m15, m15_sweep_index))
    if h1_sweep_direction == direction and h1_sweep_index is not None:
        sweep_candidates.append((h1[h1_sweep_index].time, h1, h1_sweep_index))
    sweep_candidates.sort(key=lambda candidate: candidate[0])
    entry_candles: Sequence[Candle] = (
        sweep_candidates[-1][1]
        if sweep_candidates
        else m15
        if len(m15) >= 25
        else h1
    )
    sweep_index = sweep_candidates[-1][2] if sweep_candidates else None
    sweep = bool(sweep_candidates)
    shift_index = _structure_shift_index(entry_candles, direction, sweep_index)
    shift = shift_index is not None
    post_shift = entry_candles[shift_index:] if shift_index is not None else ()
    ob, ob_stop = _mitigated_order_block(post_shift, direction, price)
    fvg = _mitigated_imbalance(post_shift, direction, price)
    atr = _atr(entry_candles)
    h1_atr = _atr(h1)
    reference_swings = _swing_points(
        h1, "low" if direction == "BUY" else "high"
    )[-10:]
    liquidity_identified = (
        direction in ("BUY", "SELL")
        and h1_atr > 0
        and any(
            abs(price - swing.price) <= h1_atr * 2
            for swing in reference_swings
        )
    )
    displacement_start = (
        sweep_index + 1 if sweep_index is not None else len(entry_candles)
    )
    displacement = (
        atr > 0
        and any(
            (
                candle.close - candle.open >= atr * 0.8
                if direction == "BUY"
                else candle.open - candle.close >= atr * 0.8
            )
            for candle in entry_candles[displacement_start:]
        )
    )
    entry_zone = ob or fvg
    entry = quote.ask if direction == "BUY" else quote.bid
    recent_candles = entry_candles[-5:]
    if not recent_candles or direction == "RANGE":
        structural_stop = entry
    elif direction == "BUY":
        structural_stop = min(candle.low for candle in recent_candles)
    else:
        structural_stop = max(candle.high for candle in recent_candles)
    if ob_stop is not None:
        structural_stop = (
            min(structural_stop, ob_stop)
            if direction == "BUY"
            else max(structural_stop, ob_stop)
        )
    stop = (
        structural_stop - atr * 0.1
        if direction == "BUY"
        else structural_stop + atr * 0.1
    )
    risk = entry - stop if direction == "BUY" else stop - entry
    risk_reward = (
        2.0
        if direction in ("BUY", "SELL") and risk > 0 and atr > 0
        else None
    )
    criteria = {
        "h4_trend_alignment": (
            direction in ("BUY", "SELL") and h4_bias == direction
        ),
        "h1_structure_alignment": (
            direction in ("BUY", "SELL") and h1_bias == direction
        ),
        "liquidity_identified": liquidity_identified,
        "liquidity_sweep": sweep,
        "structure_shift": shift,
        "displacement": displacement,
        "entry_zone": entry_zone,
        "risk_reward": risk_reward is not None,
    }
    quality_score = _score(criteria)
    criteria.update(
        {
            "h4_structure": h4_bias in ("BUY", "SELL"),
            "h1_structure": (
                direction in ("BUY", "SELL") and h1_bias == direction
            ),
            "order_block": ob,
            "fvg": fvg,
        }
    )
    target = entry + risk * 2 if direction == "BUY" else entry - risk * 2
    is_signal = (
        direction in ("BUY", "SELL")
        and quality_score >= 7
        and risk_reward is not None
    )
    status = (
        "STRONG"
        if is_signal and quality_score >= 10
        else "MEDIUM"
        if is_signal
        else "WAIT"
    )
    check_labels = (
        ("h4_trend_alignment", "4H trend alignment"),
        ("h1_structure_alignment", "1H structure alignment"),
        ("liquidity_identified", "nearby liquidity"),
        ("liquidity_sweep", "liquidity sweep"),
        ("structure_shift", "15M BOS/CHoCH after sweep"),
        ("displacement", "directional displacement"),
        ("entry_zone", "mitigated entry zone"),
        ("risk_reward", "valid stop and 2:1 risk/reward"),
    )
    missing_checks = [
        label for name, label in check_labels if not criteria[name]
    ]
    if direction == "RANGE":
        reason = (
            f"No directional setup ({quality_score}/13). "
            "Waiting for a clear 4H or 1H structure bias."
        )
    elif status == "WAIT":
        reason = (
            f"No signal ({quality_score}/13; at least 7 required). "
            "Waiting for " + ", ".join(missing_checks) + "."
            if missing_checks
            else (
                f"No signal ({quality_score}/13); valid stop and target risk "
                "are unavailable."
            )
        )
    else:
        quality = "High" if status == "STRONG" else "Medium"
        reason = (
            f"{quality} {direction} market-mechanism signal ({quality_score}/13). "
            + (
                "Confirmed: "
                + ", ".join(
                    label for name, label in check_labels if criteria[name]
                )
                + ". "
                if any(criteria[name] for name, _ in check_labels)
                else ""
            )
            + (
                "Still waiting for " + ", ".join(missing_checks) + "."
                if missing_checks
                else "All scored conditions are confirmed."
            )
        )

    result.update(
        {
            "direction": direction if is_signal else "WAIT",
            "status": status,
            "quality_score": quality_score,
            "timeframes": {
                "4h": h4_bias,
                "1h": h1_bias,
                "15m": (
                    m15_sweep_direction
                    if m15_sweep_direction == direction
                    else m15_bias
                ),
            },
            "criteria": criteria,
            "chart_patterns": _chart_patterns(
                {"1h": h1, "15m": m15},
                price=price,
                h4_bias=h4_bias,
            ),
            "entry": round(entry, quote.digits) if is_signal else None,
            "stop_loss": round(stop, quote.digits) if is_signal else None,
            "take_profit": round(target, quote.digits) if is_signal else None,
            "risk_reward": risk_reward if is_signal else None,
            "reason": reason,
        }
    )
    return result


def _serialize_candles(candles: Sequence[Candle]) -> list[dict[str, object]]:
    return [
        {
            "time_utc": datetime.fromtimestamp(
                candle.time, timezone.utc
            ).isoformat(),
            "open": candle.open,
            "high": candle.high,
            "low": candle.low,
            "close": candle.close,
        }
        for candle in candles
    ]
