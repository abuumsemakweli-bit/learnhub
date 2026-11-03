import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smc_trader/market_feed.dart';

void main() {
  test(
    'demo account requests include the session token and parse positions',
    () async {
      final service = DemoTradingService(
        client: MockClient((request) async {
          expect(request.headers['authorization'], 'Bearer session-token');
          expect(request.url.path, '/api/account');
          return http.Response(
            jsonEncode({
              'login': 5653925,
              'server': 'Headway-Demo',
              'account_mode': 'demo',
              'currency': 'USD',
              'balance': 10000,
              'equity': 9950,
              'profit': -50,
              'margin': 100,
              'free_margin': 9850,
              'positions': [
                {
                  'ticket': 7,
                  'symbol': 'EURUSD',
                  'direction': 'BUY',
                  'volume': 0.01,
                  'open_price': 1.1,
                  'stop_loss': 1.09,
                  'take_profit': 1.12,
                  'profit': -50,
                },
              ],
            }),
            200,
          );
        }),
      )..accessToken = 'session-token';

      final account = await service.fetchAccount(
        MarketFeedService.defaultBaseUrl,
      );

      expect(account.login, 5653925);
      expect(account.balance, 10000);
      expect(account.positions.single.symbol, 'EURUSD');
      expect(account.positions.single.direction, 'BUY');
      service.close();
    },
  );

  test('account connection sends credentials only to the local API', () async {
    final service = DemoTradingService(
      client: MockClient((request) async {
        expect(request.headers['authorization']?.startsWith('Bearer '), isTrue);
        expect(request.url.path, '/api/account/connect');
        expect(jsonDecode(request.body), {
          'login': '123456',
          'password': 'test-password',
          'server': 'Broker-Demo',
          'account_mode': 'demo',
        });
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
      }),
    )..accessToken = 'session-token';

    final account = await service.connectAccount(
      MarketFeedService.defaultBaseUrl,
      login: '123456',
      password: 'test-password',
      server: 'Broker-Demo',
      accountMode: 'demo',
    );

    expect(account.login, 123456);
    expect(account.server, 'Broker-Demo');
    expect(account.accountMode, 'demo');
    service.close();
  });

  test('order preview sends the selected setup and risk setting', () async {
    final service = DemoTradingService(
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer session-token');
        expect(request.url.path, '/api/order/preview');
        expect(jsonDecode(request.body), {
          'symbol': 'EURUSD',
          'direction': 'BUY',
          'risk_percent': 0.25,
        });
        return http.Response(
          jsonEncode({
            'preview_id': 'preview-1',
            'symbol': 'EURUSD',
            'direction': 'BUY',
            'volume': 0.01,
            'risk_percent': 0.25,
            'risk_amount': 2.5,
            'currency': 'USD',
            'entry': 1.1,
            'stop_loss': 1.09,
            'take_profit': 1.12,
            'score': 8,
            'score_max': 13,
          }),
          200,
        );
      }),
    )..accessToken = 'session-token';

    final preview = await service.previewOrder(
      MarketFeedService.defaultBaseUrl,
      symbol: 'EURUSD',
      direction: 'BUY',
      riskPercent: 0.25,
    );

    expect(preview.id, 'preview-1');
    expect(preview.volume, 0.01);
    expect(preview.riskAmount, 2.5);
    expect(preview.score, 8);
    expect(preview.scoreMax, 13);
    service.close();
  });

  test('manual order review sends account mode and risk limit', () async {
    final service = DemoTradingService(
      client: MockClient((request) async {
        expect(request.url.path, '/api/order-review/config');
        expect(jsonDecode(request.body), {
          'account_mode': 'live',
          'enabled': true,
          'risk_percent': 0.5,
        });
        return http.Response(
          jsonEncode({
            'account_mode': 'live',
            'enabled': true,
            'risk_percent': 0.5,
          }),
          200,
        );
      }),
    )..accessToken = 'session-token';

    final response = await service.configureOrderReview(
      MarketFeedService.defaultBaseUrl,
      accountMode: 'live',
      enabled: true,
      riskPercent: 0.5,
    );

    expect(response['enabled'], isTrue);
    service.close();
  });

  test('bot configuration sends explicit live confirmation', () async {
    final service = DemoTradingService(
      client: MockClient((request) async {
        expect(request.url.path, '/api/bot/config');
        expect(jsonDecode(request.body), {
          'account_mode': 'live',
          'enabled': true,
          'live_confirmation': true,
        });
        return http.Response(
          jsonEncode({'account_mode': 'live', 'enabled': true}),
          200,
        );
      }),
    )..accessToken = 'session-token';

    final response = await service.configureBot(
      MarketFeedService.defaultBaseUrl,
      accountMode: 'live',
      enabled: true,
      liveConfirmation: true,
    );

    expect(response['enabled'], isTrue);
    service.close();
  });

  test('history requests broker deals and parses net results', () async {
    final service = DemoTradingService(
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer session-token');
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
                'profit': 2.2,
                'commission': -0.1,
                'swap': 0,
                'fee': 0,
                'net_profit': 2.1,
                'currency': 'USD',
                'automated': true,
              },
            ],
          }),
          200,
        );
      }),
    )..accessToken = 'session-token';

    final history = await service.fetchHistory(
      MarketFeedService.defaultBaseUrl,
    );

    expect(history.accountMode, 'demo');
    expect(history.deals.single.ticket, 18);
    expect(history.deals.single.netProfit, 2.1);
    expect(history.deals.single.automated, isTrue);
    service.close();
  });

  test('demo account access is unavailable without a session token', () async {
    final service = DemoTradingService(
      client: MockClient((_) async => http.Response('{}', 200)),
    );

    await expectLater(
      service.fetchAccount(MarketFeedService.defaultBaseUrl),
      throwsA(isA<MarketFeedException>()),
    );
    service.close();
  });
}
