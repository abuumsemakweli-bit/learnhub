import 'dart:convert';

import 'package:flutter/material.dart'
    show
        Brightness,
        DropdownButton,
        Icons,
        MaterialApp,
        Size,
        SizedBox,
        SwitchListTile,
        Text,
        ValueKey,
        Widget;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smc_trader/main.dart';
import 'package:smc_trader/market_feed.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('dashboard displays only data from the connected live feed', (
    tester,
  ) async {
    _useDesktopViewport(tester);

    await tester.pumpWidget(_appWithFeed());
    await tester.pumpAndSettle();

    expect(find.text('Live market overview'), findsOneWidget);
    expect(find.text('FEED LIVE'), findsOneWidget);
    expect(find.text('EURUSD'), findsNWidgets(2));
    expect(find.text('GBPUSD'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('overview-chart-EURUSD')), findsOneWidget);
    expect(find.byKey(const ValueKey('overview-chart-GBPUSD')), findsOneWidget);
    expect(find.text('All pair charts · 1-hour candles'), findsOneWidget);
    expect(find.text('5653925'), findsNothing);
    expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
    expect(find.text('JD'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings light theme toggle updates and persists appearance', (
    tester,
  ) async {
    _useDesktopViewport(tester);

    await tester.pumpWidget(_appWithFeed());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();

    final toggle = find.byKey(const ValueKey('light-theme-toggle'));
    expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.brightness,
      Brightness.light,
    );
    expect(
      (await SharedPreferences.getInstance()).getBool('light_theme'),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_appWithFeed());
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).theme!.brightness,
      Brightness.light,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('signal filters show only matching live directions', (
    tester,
  ) async {
    _useDesktopViewport(tester);

    await tester.pumpWidget(_appWithFeed());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Signals').first);
    await tester.pumpAndSettle();

    expect(find.text('Signal feed'), findsOneWidget);
    expect(find.text('EURUSD'), findsOneWidget);
    expect(
      find.text('Market setup · 8/13 points · 5/8 checks'),
      findsNWidgets(2),
    );
    expect(find.text('15M BOS / CHoCH'), findsNWidgets(2));
    expect(find.text('Nearby liquidity'), findsNWidgets(2));
    await tester.tap(find.text('Sell'));
    await tester.pumpAndSettle();

    expect(find.text('GBPUSD'), findsOneWidget);
    expect(find.text('EURUSD'), findsNothing);
  });

  testWidgets('analysis timeframe controls update the selected interval', (
    tester,
  ) async {
    _useDesktopViewport(tester);

    await tester.pumpWidget(_appWithFeed());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analysis').first);
    await tester.pumpAndSettle();

    expect(find.text('8'), findsOneWidget);
    expect(find.text('Live broker quote'), findsOneWidget);
    final timeframeText = find.byKey(const ValueKey('chart-timeframe-4H'));
    final inactiveColor = tester.widget<Text>(timeframeText).style?.color;
    await tester.tap(timeframeText);
    await tester.pumpAndSettle();
    expect(
      tester.widget<Text>(timeframeText).style?.color,
      isNot(inactiveColor),
    );
  });

  testWidgets('analysis pair selector changes the selected market', (
    tester,
  ) async {
    _useDesktopViewport(tester);

    await tester.pumpWidget(_appWithFeed());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Analysis').first);
    await tester.pumpAndSettle();

    final pairSelector = find.byKey(const ValueKey('analysis-pair-selector'));
    expect(tester.widget<DropdownButton<String>>(pairSelector).value, 'EURUSD');
    await tester.tap(pairSelector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('GBPUSD').last);
    await tester.pumpAndSettle();

    expect(tester.widget<DropdownButton<String>>(pairSelector).value, 'GBPUSD');
    expect(find.text('Fair value gap'), findsOneWidget);
    expect(find.text('Suggested retest entry'), findsOneWidget);
    expect(find.textContaining('Market-mechanism scorecard'), findsOneWidget);
    expect(find.text('Liquidity sweep'), findsAtLeastNWidgets(1));
    expect(find.text('Order block confluence'), findsAtLeastNWidgets(1));
    expect(
      find.textContaining('evidence score, not a probability'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline feed displays no fabricated market prices', (
    tester,
  ) async {
    _useDesktopViewport(tester);

    await tester.pumpWidget(
      _appWithFeed(statusCode: 503, body: {'error': 'Feed unavailable.'}),
    );
    await tester.pumpAndSettle();

    expect(find.text('FEED OFFLINE'), findsOneWidget);
    expect(
      find.text('No live quotes. Check the MT5 feed connection.'),
      findsOneWidget,
    );
    expect(find.text('EURUSD'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('positions page keeps account, positions, and chart views', (
    tester,
  ) async {
    _useDesktopViewport(tester);

    final feed = _liveFeedPayload();
    (feed['markets'] as List<Map<String, Object?>>).add(
      _market('XAUUSD', 'WAIT'),
    );
    await tester.pumpWidget(_appWithFeed(body: feed));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Positions').first);
    await tester.pumpAndSettle();

    expect(find.text('Account & positions'), findsOneWidget);
    expect(find.text('Account summary'), findsOneWidget);
    expect(find.text('Connect MT5 account in Settings'), findsOneWidget);
    expect(find.text('EURUSD position chart'), findsOneWidget);
    expect(find.text('USDCAD position chart'), findsOneWidget);
    expect(find.text('XAUUSD position chart'), findsOneWidget);
    expect(find.text('Open positions'), findsOneWidget);
    expect(find.text('Bot execution rules'), findsNothing);
    expect(find.text('Signal suggestions'), findsNothing);
    expect(find.textContaining('EMA '), findsNothing);
    expect(find.text('RSI(14)'), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey('eurusd-position-chart-timeframe-5M')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('EMA '), findsNothing);
    expect(find.text('RSI(14)'), findsNothing);
    expect(
      find.byKey(const ValueKey('usdcad-position-chart-timeframe-1H')),
      findsNothing,
    );
    await tester.tap(find.text('Connect MT5 account in Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings & accounts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'history page shows a clear connection error and refresh action',
    (tester) async {
      _useDesktopViewport(tester);

      await tester.pumpWidget(_appWithFeed());
      await tester.pumpAndSettle();
      await tester.tap(find.text('History').first);
      await tester.pumpAndSettle();

      expect(find.text('Trade history'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Trade history')).dy, lessThan(120));
      expect(find.text('History unavailable'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('history page displays only ARTIFACTS bot executions', (
    tester,
  ) async {
    _useDesktopViewport(tester);
    final historyService = DemoTradingService(
      client: MockClient((request) async {
        if (request.url.path == '/api/account') {
          return http.Response(
            jsonEncode({
              'login': 123456,
              'server': 'Broker-Demo',
              'account_mode': 'demo',
              'currency': 'USD',
              'balance': 1000,
              'equity': 1000,
              'profit': 0,
              'margin': 0,
              'free_margin': 1000,
              'positions': [],
            }),
            200,
          );
        }
        expect(request.url.path, '/api/history');
        return http.Response(
          jsonEncode({
            'account_mode': 'demo',
            'currency': 'USD',
            'days': 30,
            'deals': [
              {
                'ticket': 18,
                'time_utc': '2026-10-23T12:00:00+00:00',
                'symbol': 'EURUSD',
                'direction': 'BUY',
                'entry': 'OUT',
                'volume': 0.01,
                'price': 1.12345,
                'net_profit': 2.1,
                'currency': 'USD',
                'automated': true,
              },
              {
                'ticket': 19,
                'time_utc': '2026-10-23T11:00:00+00:00',
                'symbol': 'GBPUSD',
                'direction': 'SELL',
                'entry': 'OUT',
                'volume': 0.02,
                'price': 1.22345,
                'net_profit': -1.0,
                'currency': 'USD',
                'automated': false,
              },
            ],
          }),
          200,
        );
      }),
    )..accessToken = 'session-token';
    addTearDown(historyService.close);

    await tester.pumpWidget(_appWithFeed(tradingService: historyService));
    await tester.pumpAndSettle();
    await tester.tap(find.text('History').first);
    await tester.pumpAndSettle();

    expect(find.text('EURUSD'), findsOneWidget);
    expect(find.text('GBPUSD'), findsNothing);
    expect(find.text('+2.10'), findsOneWidget);
    expect(find.text('All activity'), findsNothing);
    expect(find.text('ARTIFACTS bot activity'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings lets users enter broker account credentials', (
    tester,
  ) async {
    _useDesktopViewport(tester);

    await tester.pumpWidget(_appWithFeed());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings').first);
    await tester.pumpAndSettle();

    expect(find.text('MT5 ACCOUNT LOGIN'), findsOneWidget);
    expect(find.text('BROKER SERVER'), findsOneWidget);
    expect(find.text('MT5 TRADING PASSWORD'), findsOneWidget);
    expect(find.text('Connect MT5 account'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mt5-account-connection-status')),
      findsOneWidget,
    );
    expect(
      find.text(
        'The secure local MT5 service is not running in this app session. Start or retry the local service below.',
      ),
      findsOneWidget,
    );
    expect(find.text('Start / retry local MT5 service'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile navigation exposes additional screens', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_appWithFeed());
    await tester.pumpAndSettle();
    expect(find.text('Live market overview'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Automation'));
    await tester.pumpAndSettle();

    expect(find.text('Automation controls'), findsOneWidget);
    expect(find.text('Automated bot disabled'), findsOneWidget);
    expect(find.text('Enable automated bot'), findsOneWidget);
    expect(find.text('Manual order review disabled'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _appWithFeed({
  int statusCode = 200,
  Map<String, Object?>? body,
  DemoTradingService? tradingService,
}) {
  final feedService = MarketFeedService(
    client: MockClient((request) async {
      expect(request.url.path, '/api/market/signals');
      return http.Response(jsonEncode(body ?? _liveFeedPayload()), statusCode);
    }),
  );
  addTearDown(feedService.close);

  final activeTradingService = tradingService ?? DemoTradingService();
  if (tradingService == null) addTearDown(activeTradingService.close);
  return SMCTraderApp(
    marketFeedService: feedService,
    demoTradingService: activeTradingService,
  );
}

Map<String, Object?> _liveFeedPayload() => {
  'source': 'MetaTrader 5',
  'generated_at_utc': DateTime.utc(2026, 10, 28).toIso8601String(),
  'account_connected': true,
  'read_only': true,
  'markets': [_market('EURUSD', 'BUY'), _market('GBPUSD', 'SELL')],
};

Map<String, Object?> _market(String symbol, String direction) => {
  'symbol': symbol,
  'direction': direction,
  'status': direction == 'WAIT' ? 'WAIT' : 'STRONG',
  'quality_score': 8,
  'quality_score_max': 13,
  'entry': 1.101,
  'stop_loss': 1.099,
  'take_profit': 1.105,
  'reason': 'Closed-candle market analysis.',
  'bid': 1.1,
  'ask': 1.1001,
  'spread_pips': 1.0,
  'quote_age_seconds': 2,
  'quote_time_utc': DateTime.utc(2026, 10, 28).toIso8601String(),
  'timeframes': {'4h': 'BUY', '1h': 'BUY', '15m': direction},
  'criteria': {
    'h4_trend_alignment': true,
    'h1_structure_alignment': true,
    'liquidity_identified': false,
    'liquidity_sweep': true,
    'structure_shift': false,
    'displacement': true,
    'entry_zone': true,
    'risk_reward': false,
    'order_block': true,
    'fvg': true,
  },
  'candle_history': {
    '4h': _candles(),
    '1h': _candles(),
    '15m': _candles(),
    '5m': _candles(),
  },
  'chart_patterns': [_pattern('fvg'), _pattern('order_block')],
};

List<Map<String, Object?>> _candles() => [
  for (var index = 0; index < 12; index++)
    {
      'time_utc': DateTime.utc(2026, 10, 28, 12, index).toIso8601String(),
      'open': 1.1 + index * 0.0001,
      'high': 1.101 + index * 0.0001,
      'low': 1.099 + index * 0.0001,
      'close': 1.1005 + index * 0.0001,
    },
];

Map<String, Object?> _pattern(String type) => {
  'type': type,
  'timeframe': '1h',
  'direction': 'BUY',
  'start_time_utc': DateTime.utc(2026, 10, 28, 10).toIso8601String(),
  'end_time_utc': DateTime.utc(2026, 10, 28, 11).toIso8601String(),
  'low': 1.099,
  'high': 1.101,
  'level': 1.1,
  'confluence_score': 75,
  'entry': 1.1,
};
