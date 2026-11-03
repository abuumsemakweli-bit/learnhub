import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class MarketCandle {
  const MarketCandle({
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });

  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;

  factory MarketCandle.fromJson(Map<String, dynamic> json) {
    return MarketCandle(
      time: DateTime.parse(json['time_utc'] as String).toLocal(),
      open: (json['open'] as num).toDouble(),
      high: (json['high'] as num).toDouble(),
      low: (json['low'] as num).toDouble(),
      close: (json['close'] as num).toDouble(),
    );
  }
}

class ChartPattern {
  const ChartPattern({
    required this.type,
    required this.timeframe,
    required this.direction,
    required this.startTime,
    required this.endTime,
    required this.low,
    required this.high,
    required this.level,
    required this.confluenceScore,
    required this.entry,
  });

  final String type;
  final String timeframe;
  final String direction;
  final DateTime startTime;
  final DateTime endTime;
  final double low;
  final double high;
  final double? level;
  final int? confluenceScore;
  final double? entry;

  factory ChartPattern.fromJson(Map<String, dynamic> json) => ChartPattern(
    type: json['type'] as String,
    timeframe: json['timeframe'] as String,
    direction: json['direction'] as String,
    startTime: DateTime.parse(json['start_time_utc'] as String).toLocal(),
    endTime: DateTime.parse(json['end_time_utc'] as String).toLocal(),
    low: (json['low'] as num).toDouble(),
    high: (json['high'] as num).toDouble(),
    level: (json['level'] as num?)?.toDouble(),
    confluenceScore: (json['confluence_score'] as num?)?.toInt(),
    entry: (json['entry'] as num?)?.toDouble(),
  );
}

class MarketSignal {
  const MarketSignal({
    required this.pair,
    required this.direction,
    required this.status,
    required this.score,
    required this.scoreMax,
    required this.entry,
    required this.stop,
    required this.target,
    required this.time,
    required this.setup,
    required this.bid,
    required this.ask,
    required this.spreadPips,
    required this.quoteAgeSeconds,
    required this.timeframes,
    required this.criteria,
    required this.candles,
    required this.chartPatterns,
  });

  final String pair;
  final String direction;
  final String status;
  final int score;
  final int scoreMax;
  final String entry;
  final String stop;
  final String target;
  final String time;
  final String setup;
  final double bid;
  final double ask;
  final double? spreadPips;
  final int quoteAgeSeconds;
  final Map<String, String> timeframes;
  final Map<String, bool> criteria;
  final Map<String, List<MarketCandle>> candles;
  final List<ChartPattern> chartPatterns;

  bool get hasSignal => direction == 'BUY' || direction == 'SELL';

  factory MarketSignal.fromJson(Map<String, dynamic> json) {
    final candleJson = json['candle_history'] as Map<String, dynamic>? ?? {};
    final frameCandles = <String, List<MarketCandle>>{};
    for (final entry in candleJson.entries) {
      frameCandles[entry.key] = (entry.value as List<dynamic>)
          .map((item) => MarketCandle.fromJson(item as Map<String, dynamic>))
          .toList(growable: false);
    }
    final rawTimeframes =
        json['timeframes'] as Map<String, dynamic>? ?? const {};
    final rawCriteria = json['criteria'] as Map<String, dynamic>? ?? const {};
    final rawPatterns = json['chart_patterns'] as List<dynamic>? ?? const [];

    return MarketSignal(
      pair: json['symbol'] as String,
      direction: json['direction'] as String? ?? 'WAIT',
      status: json['status'] as String? ?? 'WAIT',
      score: (json['quality_score'] as num? ?? 0).toInt(),
      scoreMax: (json['quality_score_max'] as num? ?? 13).toInt(),
      entry: _formatPrice(json['entry']),
      stop: _formatPrice(json['stop_loss']),
      target: _formatPrice(json['take_profit']),
      time: _formatLocalTime(json['quote_time_utc'] as String?),
      setup: json['reason'] as String? ?? 'No valid setup.',
      bid: (json['bid'] as num).toDouble(),
      ask: (json['ask'] as num).toDouble(),
      spreadPips: (json['spread_pips'] as num?)?.toDouble(),
      quoteAgeSeconds: (json['quote_age_seconds'] as num? ?? 0).toInt(),
      timeframes: rawTimeframes.map(
        (key, value) => MapEntry(key, value.toString()),
      ),
      criteria: rawCriteria.map((key, value) => MapEntry(key, value == true)),
      candles: frameCandles,
      chartPatterns: rawPatterns
          .map((item) => ChartPattern.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  static String _formatPrice(Object? value) {
    if (value is! num) return '—';
    return value.toString();
  }

  static String _formatLocalTime(String? value) {
    if (value == null) return '—';
    final time = DateTime.parse(value).toLocal();
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }
}

class MarketFeedSnapshot {
  const MarketFeedSnapshot({
    required this.source,
    required this.generatedAt,
    required this.markets,
  });

  final String source;
  final DateTime generatedAt;
  final List<MarketSignal> markets;

  factory MarketFeedSnapshot.fromJson(Map<String, dynamic> json) {
    if (json['account_connected'] != true || json['read_only'] != true) {
      throw const FormatException(
        'The configured market-data service is not a read-only connected feed.',
      );
    }
    return MarketFeedSnapshot(
      source: json['source'] as String,
      generatedAt: DateTime.parse(json['generated_at_utc'] as String).toLocal(),
      markets: (json['markets'] as List<dynamic>)
          .map((item) => MarketSignal.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
    );
  }
}

class MarketFeedException implements Exception {
  const MarketFeedException(this.message);

  final String message;

  @override
  String toString() => message;
}

class DemoPosition {
  const DemoPosition({
    required this.ticket,
    required this.symbol,
    required this.direction,
    required this.volume,
    required this.openPrice,
    required this.stopLoss,
    required this.takeProfit,
    required this.profit,
  });

  final int ticket;
  final String symbol;
  final String direction;
  final double volume;
  final double openPrice;
  final double stopLoss;
  final double takeProfit;
  final double profit;

  factory DemoPosition.fromJson(Map<String, dynamic> json) => DemoPosition(
    ticket: (json['ticket'] as num).toInt(),
    symbol: json['symbol'] as String,
    direction: json['direction'] as String,
    volume: (json['volume'] as num).toDouble(),
    openPrice: (json['open_price'] as num).toDouble(),
    stopLoss: (json['stop_loss'] as num).toDouble(),
    takeProfit: (json['take_profit'] as num).toDouble(),
    profit: (json['profit'] as num).toDouble(),
  );
}

class DemoAccountSnapshot {
  const DemoAccountSnapshot({
    required this.login,
    required this.server,
    required this.accountMode,
    required this.currency,
    required this.balance,
    required this.equity,
    required this.profit,
    required this.margin,
    required this.freeMargin,
    required this.positions,
  });

  final int login;
  final String server;
  final String accountMode;
  final String currency;
  final double balance;
  final double equity;
  final double profit;
  final double margin;
  final double freeMargin;
  final List<DemoPosition> positions;

  factory DemoAccountSnapshot.fromJson(Map<String, dynamic> json) =>
      DemoAccountSnapshot(
        login: (json['login'] as num).toInt(),
        server: json['server'] as String,
        accountMode: json['account_mode'] as String,
        currency: json['currency'] as String,
        balance: (json['balance'] as num).toDouble(),
        equity: (json['equity'] as num).toDouble(),
        profit: (json['profit'] as num).toDouble(),
        margin: (json['margin'] as num).toDouble(),
        freeMargin: (json['free_margin'] as num).toDouble(),
        positions: (json['positions'] as List<dynamic>)
            .map((item) => DemoPosition.fromJson(item as Map<String, dynamic>))
            .toList(growable: false),
      );
}

class DemoOrderPreview {
  const DemoOrderPreview({
    required this.id,
    required this.symbol,
    required this.direction,
    required this.volume,
    required this.riskPercent,
    required this.riskAmount,
    required this.currency,
    required this.entry,
    required this.stopLoss,
    required this.takeProfit,
    required this.score,
    required this.scoreMax,
  });

  final String id;
  final String symbol;
  final String direction;
  final double volume;
  final double riskPercent;
  final double riskAmount;
  final String currency;
  final double entry;
  final double stopLoss;
  final double takeProfit;
  final int score;
  final int scoreMax;

  factory DemoOrderPreview.fromJson(Map<String, dynamic> json) =>
      DemoOrderPreview(
        id: json['preview_id'] as String,
        symbol: json['symbol'] as String,
        direction: json['direction'] as String,
        volume: (json['volume'] as num).toDouble(),
        riskPercent: (json['risk_percent'] as num).toDouble(),
        riskAmount: (json['risk_amount'] as num).toDouble(),
        currency: json['currency'] as String,
        entry: (json['entry'] as num).toDouble(),
        stopLoss: (json['stop_loss'] as num).toDouble(),
        takeProfit: (json['take_profit'] as num).toDouble(),
        score: (json['score'] as num).toInt(),
        scoreMax: (json['score_max'] as num? ?? 100).toInt(),
      );
}

class DemoOrderResult {
  const DemoOrderResult({
    required this.order,
    required this.symbol,
    required this.direction,
    required this.strategy,
    required this.volume,
    required this.price,
    required this.riskAmount,
    required this.currency,
  });

  final int order;
  final String symbol;
  final String direction;
  final String? strategy;
  final double volume;
  final double price;
  final double riskAmount;
  final String currency;

  factory DemoOrderResult.fromJson(Map<String, dynamic> json) =>
      DemoOrderResult(
        order: (json['order'] as num).toInt(),
        symbol: json['symbol'] as String,
        direction: json['direction'] as String,
        strategy: json['strategy'] as String?,
        volume: (json['volume'] as num).toDouble(),
        price: (json['price'] as num).toDouble(),
        riskAmount: (json['risk_amount'] as num).toDouble(),
        currency: json['currency'] as String,
      );
}

class TradeHistoryEntry {
  const TradeHistoryEntry({
    required this.ticket,
    required this.time,
    required this.symbol,
    required this.direction,
    required this.entry,
    required this.volume,
    required this.price,
    required this.netProfit,
    required this.currency,
    required this.automated,
  });

  final int ticket;
  final DateTime time;
  final String symbol;
  final String direction;
  final String entry;
  final double volume;
  final double price;
  final double netProfit;
  final String currency;
  final bool automated;

  factory TradeHistoryEntry.fromJson(Map<String, dynamic> json) =>
      TradeHistoryEntry(
        ticket: (json['ticket'] as num).toInt(),
        time: DateTime.parse(json['time_utc'] as String).toLocal(),
        symbol: json['symbol'] as String,
        direction: json['direction'] as String,
        entry: json['entry'] as String,
        volume: (json['volume'] as num).toDouble(),
        price: (json['price'] as num).toDouble(),
        netProfit: (json['net_profit'] as num).toDouble(),
        currency: json['currency'] as String,
        automated: json['automated'] as bool,
      );
}

class TradeHistorySnapshot {
  const TradeHistorySnapshot({
    required this.accountMode,
    required this.currency,
    required this.deals,
  });

  final String accountMode;
  final String currency;
  final List<TradeHistoryEntry> deals;

  factory TradeHistorySnapshot.fromJson(Map<String, dynamic> json) =>
      TradeHistorySnapshot(
        accountMode: json['account_mode'] as String,
        currency: json['currency'] as String,
        deals: (json['deals'] as List<dynamic>)
            .map(
              (item) =>
                  TradeHistoryEntry.fromJson(item as Map<String, dynamic>),
            )
            .toList(growable: false),
      );
}

class DemoTradingService {
  DemoTradingService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String? accessToken;

  Future<TradeHistorySnapshot> fetchHistory(String baseUrl) async {
    final response = await _send(baseUrl, 'GET', '/api/history');
    try {
      return TradeHistorySnapshot.fromJson(response);
    } on FormatException catch (error) {
      throw MarketFeedException(
        'Invalid trade history response: ${error.message}',
      );
    } on TypeError {
      throw const MarketFeedException(
        'The trade history response is missing required data.',
      );
    }
  }

  Future<DemoAccountSnapshot> connectAccount(
    String baseUrl, {
    required String login,
    required String password,
    required String server,
    required String accountMode,
  }) async {
    final response = await _send(
      baseUrl,
      'POST',
      '/api/account/connect',
      body: {
        'login': login.trim(),
        'password': password,
        'server': server.trim(),
        'account_mode': accountMode,
      },
      timeout: const Duration(seconds: 60),
    );
    try {
      return DemoAccountSnapshot.fromJson(response);
    } on FormatException catch (error) {
      throw MarketFeedException(
        'Invalid account connection response: ${error.message}',
      );
    } on TypeError {
      throw const MarketFeedException(
        'The account connection response is missing required data.',
      );
    }
  }

  Future<DemoAccountSnapshot> fetchAccount(String baseUrl) async {
    final response = await _send(baseUrl, 'GET', '/api/account');
    try {
      return DemoAccountSnapshot.fromJson(response);
    } on FormatException catch (error) {
      throw MarketFeedException(
        'Invalid demo account response: ${error.message}',
      );
    } on TypeError {
      throw const MarketFeedException(
        'The demo account response is missing required account data.',
      );
    }
  }

  Future<Map<String, dynamic>> configureOrderReview(
    String baseUrl, {
    required String accountMode,
    required bool enabled,
    required double riskPercent,
  }) => _send(
    baseUrl,
    'POST',
    '/api/order-review/config',
    body: {
      'account_mode': accountMode,
      'enabled': enabled,
      'risk_percent': riskPercent,
    },
  );

  Future<Map<String, dynamic>> configureBot(
    String baseUrl, {
    required String accountMode,
    required bool enabled,
    required bool liveConfirmation,
  }) => _send(
    baseUrl,
    'POST',
    '/api/bot/config',
    body: {
      'account_mode': accountMode,
      'enabled': enabled,
      'live_confirmation': liveConfirmation,
    },
  );

  Future<DemoOrderPreview> previewOrder(
    String baseUrl, {
    required String symbol,
    required String direction,
    required double riskPercent,
  }) async {
    final response = await _send(
      baseUrl,
      'POST',
      '/api/order/preview',
      body: {
        'symbol': symbol,
        'direction': direction,
        'risk_percent': riskPercent,
      },
    );
    try {
      return DemoOrderPreview.fromJson(response);
    } on FormatException catch (error) {
      throw MarketFeedException('Invalid order preview: ${error.message}');
    } on TypeError {
      throw const MarketFeedException(
        'The demo service returned an incomplete order preview.',
      );
    }
  }

  Future<DemoOrderResult> executeOrder(
    String baseUrl, {
    required String previewId,
  }) async {
    final response = await _send(
      baseUrl,
      'POST',
      '/api/order/execute',
      body: {'preview_id': previewId},
    );
    try {
      return DemoOrderResult.fromJson(response);
    } on FormatException catch (error) {
      throw MarketFeedException('Invalid order result: ${error.message}');
    } on TypeError {
      throw const MarketFeedException(
        'The demo service returned an incomplete order result.',
      );
    }
  }

  Future<Map<String, dynamic>> _send(
    String baseUrl,
    String method,
    String path, {
    Map<String, Object>? body,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final token = accessToken;
    if (token == null || token.isEmpty) {
      throw const MarketFeedException(
        'Trading is available only through an authorized local Windows app session. Close any manually started feed and restart the app.',
      );
    }
    final normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final baseUri = Uri.tryParse(normalized);
    if (baseUri == null ||
        !baseUri.hasAuthority ||
        baseUri.scheme != 'http' ||
        !const {'127.0.0.1', 'localhost', '::1'}.contains(baseUri.host)) {
      throw const MarketFeedException(
        'Demo account access requires the local HTTP feed.',
      );
    }

    late final http.Response response;
    try {
      final uri = baseUri.replace(path: path);
      if (method == 'GET') {
        response = await _client
            .get(uri, headers: {'Authorization': 'Bearer $token'})
            .timeout(timeout);
      } else {
        response = await _client
            .post(
              uri,
              headers: {
                'Authorization': 'Bearer $token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(body),
            )
            .timeout(timeout);
      }
    } on TimeoutException {
      throw const MarketFeedException('The local demo service timed out.');
    } on http.ClientException catch (error) {
      throw MarketFeedException('Cannot reach the local demo service: $error');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const MarketFeedException(
        'The local demo service returned invalid JSON.',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const MarketFeedException(
        'The local demo service returned an unexpected response.',
      );
    }
    if (response.statusCode != 200) {
      throw MarketFeedException(
        decoded['error'] as String? ??
            'Local demo service returned HTTP ${response.statusCode}.',
      );
    }
    return decoded;
  }

  void close() => _client.close();
}

class MarketFeedService {
  static const defaultBaseUrl = 'http://127.0.0.1:8765';

  MarketFeedService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<MarketFeedSnapshot> fetch(String baseUrl) async {
    final normalized = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse('$normalized/api/market/signals');
    if (uri == null ||
        !uri.hasAuthority ||
        !const {'http', 'https'}.contains(uri.scheme)) {
      throw const MarketFeedException(
        'Enter a valid HTTP or HTTPS market-feed address.',
      );
    }
    if (!const {'127.0.0.1', 'localhost', '::1'}.contains(uri.host)) {
      throw const MarketFeedException(
        'For safety, the market feed must use a local loopback address.',
      );
    }

    late final http.Response response;
    try {
      response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 7));
    } on TimeoutException {
      throw const MarketFeedException(
        'The market feed timed out. Check that the MT5 feed is running.',
      );
    } on http.ClientException {
      throw const MarketFeedException(
        'Cannot reach the market feed. Check the service address and that it is running.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const MarketFeedException('The market feed returned invalid JSON.');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const MarketFeedException(
        'The market feed returned an unexpected response.',
      );
    }
    if (response.statusCode != 200) {
      throw MarketFeedException(
        decoded['error'] as String? ??
            'Market feed returned HTTP ${response.statusCode}.',
      );
    }

    try {
      return MarketFeedSnapshot.fromJson(decoded);
    } on FormatException catch (error) {
      throw MarketFeedException(error.message);
    } on TypeError {
      throw const MarketFeedException(
        'The market feed is missing required live quote data.',
      );
    }
  }

  void close() => _client.close();
}
