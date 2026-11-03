# ARTIFACTS Signal Pro

A responsive Flutter market-analysis app for Android, Web, and Windows. It
receives live quotes and closed-candle data from a local Python service
connected to MetaTrader 5. The Windows app is the only build that can launch
the authorized local trading service.

## MT5 connection

The Windows app starts the local feed automatically and stops the process it
started when the app closes. The app binds its session to an available loopback
port so an old or separately started feed on port 8765 cannot block its
authorized session. Python and the packages below must be installed once, and
a MetaTrader 5 terminal must be installed. The default terminal path is
`C:\Program Files\Headway MT5 Terminal\terminal64.exe`; set the
`MT5_TERMINAL_PATH` environment variable before launching the app to use a
different MT5 terminal executable.

In Settings, enter the numeric MT5 login, exact broker server name, and MT5
trading password, then choose Demo or Live and connect. Credentials are sent
only to the authorized loopback service on this computer; the app does not
persist them, and it clears the password field after each connection attempt.
MetaTrader itself may retain its own login/session according to its settings.
Connecting a Live account requires confirmation. The selected mode is checked
against the account returned by MT5, and a mismatch prevents access and trading.
If the terminal is already running but is not signed in, the service retries
by reinitializing the configured terminal with the submitted account details.
Allow up to one minute for the connection attempt; failures show the MT5 login
and terminal connection error codes without exposing the password.
Only use this feature in the Windows app; Android and Web builds cannot start
the authorized local trading service. The feed supports EURUSD, USDCAD, GBPUSD,
USDJPY, XAUUSD, AUDUSD, BTCUSD, and NASDAQ-100, including broker-prefixed versions
when the symbol can be resolved unambiguously. These last two names match the
instruments exposed by the currently configured Headway MT5 terminal.

Install feed dependencies from the project directory in PowerShell (required
once for automatic startup):

```powershell
python -m pip install -r mt5_feed\requirements.txt
```

The service listens on `127.0.0.1:8765` by default. Do not expose it beyond
loopback. Android and Web builds cannot launch the Windows service. A manually
started service supports market data, but manual order review requires the
authorized Windows app session. For Android over USB, forward the port:

```powershell
adb reverse tcp:8765 tcp:8765
```

Use `http://127.0.0.1:8765` as the feed address. The forwarding must be
recreated when the device reconnects.

## Bot and manual order controls

The Automation screen has separate switches for the automated bot and
manual order review. Both are disabled by default and reset to disabled when
the app's local MT5 service starts or an account is connected. Enabling live
bot trading requires an explicit confirmation.

The bot uses the same closed-candle analysis shown in the Signals tab. It
requires a BUY or SELL direction and a confirmed liquidity sweep. For valid
7/13 or 8/13 setups, it opens two 0.10-lot scalping positions, each with a
broker-calculated take-profit targeting $4. These two-position scalps require
an MT5 hedging account; on netting accounts, the bot skips them rather than
combining their independently managed targets. Each position retains the
existing 0.5% maximum estimated per-order risk limit, so their combined risk
can reach 1% of balance. For scores 9/13 and higher, the bot's existing
single-position behavior, signal take-profit, and add-on rules are unchanged.
XAUUSD is excluded; all other configured symbols are eligible. There is no
app-level session window: the bot checks signals every 15 seconds while the
authorized Windows app and MT5 service are running, subject to the broker's
market availability. An existing position on a symbol prevents a new initial
entry.

Initial entries for scores 9/13 and higher use 0.10 lots, with the Signal-tab
stop-loss and take-profit. The bot skips an order rather than reducing its
requested volume when broker volume rules, margin, or the 0.5% maximum
estimated per-order risk limit would be exceeded. At most one 0.01-lot add-on
is allowed per high-confirmation setup, after price has moved at least 1R in
the trade direction and retraced no more than 0.5 × 15-minute ATR(14). The
add-on must also pass the same risk and broker checks.
The stop is ratcheted to lock approximately $1 for each whole $1 of floating
profit, up to $5 locked profit; broker stop-distance rules can defer a
modification. A completed 15-minute candle with a directional body at least
1.5 × ATR(14) holds the position until 23:59 UTC that day unless its SL or TP
closes it sooner. SL and TP remain active throughout. The bot uses the
MetaTrader 5 Python API via the local service.

The 24/5 worker requires the Windows app, local service, and MT5 terminal to
remain running; sleep, shutdown, disconnection, and broker market closures
pause checks. Broker-side SL/TP remain attached to open orders if the app
closes, but trailing-stop updates and UTC day-end closes require the worker to
be running. Disabling the bot stops new entries and add-ons while it continues
managing its existing bot positions.

Manual order review is separate: each manual order must be opened from
Analysis, previewed against the current market and account, and explicitly
confirmed. Manual orders retain their 0.01-lot maximum and 0.5% per-order
estimated risk limit.

Bot and manual orders are subject to broker margin and stop-distance
constraints, and account/terminal trade permissions. Estimated stop risk is
not a guaranteed maximum: gaps, slippage, commissions, execution differences,
outages, and broker rules can cause losses to exceed the estimate.

The Positions tab retains the account summary, open positions, and plain M15/M5
price charts for EURUSD, USDCAD, and XAUUSD. History remains read-only and can
show historical ARTIFACTS bot deal records.

MT5 tick timestamps that are one whole broker-timezone offset ahead of UTC are
normalized only when they are within two minutes of the current UTC time; the
same verified offset is applied to candle timestamps from that broker. The
Analysis screen shows when quotes are stale or the local broker feed is
unavailable.

Overview, Signals, and Analysis show signals from the same closed-candle SMC
analysis. Their chart views focus on 1H candles with a 4H option for context.
The SMC signal sequence is 4H swing-structure bias, then on 1H a liquidity
sweep in the bias direction, a post-sweep MSS/BOS, and price returning to
mitigate a post-shift order block or fair value gap. Either zone is sufficient
for the final confirmation. Signals remain WAIT until that sequence is
complete. The score represents rule alignment, not a probability of profit.
Chart patterns are analysis references, not orders or guaranteed outcomes.

The Settings page includes a saved Light theme switch and account profile icon.

The app also displays account balance, equity, margin, and open positions.
Use demo mode to evaluate behavior before considering live trading. This
software provides technical analysis, not investment advice or a guarantee of
results. No real broker connection or order placement has been validated by
automated tests.
Never send broker credentials in chat or enter them anywhere except the
intended MT5 account form in the local Windows app.

## Signal limitations

Market-analysis BUY and SELL signals use a separate 13-point market-mechanism
scorecard: 4H trend, 1H structure, nearby liquidity, sweep, 15M structure
shift, displacement, entry-zone mitigation, and risk/reward. Scores 7-9 are
MEDIUM signals and scores 10-13 are STRONG signals; below 7 the app displays
WAIT. A MEDIUM signal can be reviewed for a manually confirmed order, subject
to the same live quote, stop, and account risk checks. The score measures
confluence, not a probability of profit. The History tab is read-only and
displays historical ARTIFACTS bot deal records; it does not guarantee that a
broker has reconciled every commission or correction in the same way as the app.

## Run and build the app

```powershell
flutter pub get
flutter run -d windows
flutter run -d chrome
flutter run -d <android-device-id>
```

Build release targets with:

```powershell
flutter build windows
flutter build web
flutter build apk
```

## Tests

```powershell
flutter analyze
flutter test
python -m unittest discover -s mt5_feed -v
```
