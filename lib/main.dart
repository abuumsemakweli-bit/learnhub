import 'dart:async';
import 'dart:math' show max, min;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'feed_server_launcher.dart';
import 'market_feed.dart';

void main() {
  runApp(const SMCTraderApp());
}

Color _background = const Color(0xFF0A0E13);
Color _panel = const Color(0xFF111820);
Color _panelRaised = const Color(0xFF151F29);
Color _line = const Color(0xFF202B36);
Color _muted = const Color(0xFF82909E);
Color _white = const Color(0xFFF1F5F8);
Color _lime = const Color(0xFFC2F970);
Color _green = const Color(0xFF49D6A0);
Color _red = const Color(0xFFFF747D);
Color _amber = const Color(0xFFFFC56B);
Color _blue = const Color(0xFF78A9FF);

void _applyPalette(bool light) {
  _background = Color(light ? 0xFFF3F6F8 : 0xFF0A0E13);
  _panel = Color(light ? 0xFFFFFFFF : 0xFF111820);
  _panelRaised = Color(light ? 0xFFE8EDF1 : 0xFF151F29);
  _line = Color(light ? 0xFFD5DEE5 : 0xFF202B36);
  _muted = Color(light ? 0xFF63717D : 0xFF82909E);
  _white = Color(light ? 0xFF17212B : 0xFFF1F5F8);
  _lime = Color(light ? 0xFF648A20 : 0xFFC2F970);
  _green = Color(light ? 0xFF16885E : 0xFF49D6A0);
  _red = Color(light ? 0xFFC43F50 : 0xFFFF747D);
  _amber = Color(light ? 0xFFA9650A : 0xFFFFC56B);
  _blue = Color(light ? 0xFF2867B2 : 0xFF78A9FF);
}

class SMCTraderApp extends StatefulWidget {
  const SMCTraderApp({
    super.key,
    this.marketFeedService,
    this.demoTradingService,
  });

  final MarketFeedService? marketFeedService;
  final DemoTradingService? demoTradingService;

  @override
  State<SMCTraderApp> createState() => _SMCTraderAppState();
}

class _SMCTraderAppState extends State<SMCTraderApp> {
  bool _lightTheme = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final preferences = await SharedPreferences.getInstance();
    final light = preferences.getBool('light_theme') ?? false;
    _applyPalette(light);
    if (mounted) setState(() => _lightTheme = light);
  }

  Future<void> _setTheme(bool light) async {
    _applyPalette(light);
    setState(() => _lightTheme = light);
    await (await SharedPreferences.getInstance()).setBool('light_theme', light);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _lime,
      brightness: _lightTheme ? Brightness.light : Brightness.dark,
      surface: _panel,
    );
    return MaterialApp(
      title: 'ARTIFACTS Signal Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: _lightTheme ? Brightness.light : Brightness.dark,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: _background,
        fontFamily: 'Segoe UI',
        textTheme: (_lightTheme ? ThemeData.light() : ThemeData.dark())
            .textTheme
            .apply(bodyColor: _white, displayColor: _white),
        dividerColor: _line,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _background,
          hintStyle: TextStyle(color: _muted),
          labelStyle: TextStyle(color: _muted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _lime),
          ),
        ),
      ),
      home: AppShell(
        marketFeedService: widget.marketFeedService,
        demoTradingService: widget.demoTradingService,
        lightTheme: _lightTheme,
        onLightThemeChanged: _setTheme,
      ),
    );
  }
}

const _navItems = [
  (label: 'Overview', icon: Icons.grid_view_rounded),
  (label: 'Signals', icon: Icons.bolt_rounded),
  (label: 'Analysis', icon: Icons.candlestick_chart_rounded),
  (label: 'Positions', icon: Icons.swap_vert_rounded),
  (label: 'History', icon: Icons.receipt_long_rounded),
  (label: 'Automation', icon: Icons.tune_rounded),
  (label: 'Settings', icon: Icons.settings_rounded),
];

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.marketFeedService,
    this.demoTradingService,
    required this.lightTheme,
    required this.onLightThemeChanged,
  });

  final MarketFeedService? marketFeedService;
  final DemoTradingService? demoTradingService;
  final bool lightTheme;
  final ValueChanged<bool> onLightThemeChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  bool _orderReviewEnabled = false;
  bool _botEnabled = false;
  bool _notificationsEnabled = true;
  bool _feedConnected = false;
  bool _refreshing = false;
  bool _loadingDemoAccount = false;
  bool _submittingDemoOrder = false;
  double _riskPerTrade = 0.5;
  int _selectedSignal = 0;
  String _selectedTimeframe = '1H';
  String _eurusdPositionsTimeframe = '15M';
  String _usdcadPositionsTimeframe = '15M';
  String _xauusdPositionsTimeframe = '15M';
  String _feedUrl = MarketFeedService.defaultBaseUrl;
  String _feedMessage = 'Waiting for the local Headway MT5 feed.';
  String _feedSource = 'MetaTrader 5';
  String _accountMode = 'demo';
  DateTime? _lastFeedUpdate;
  List<MarketSignal> _markets = [];
  DemoAccountSnapshot? _demoAccount;
  String _demoAccountMessage = 'Connecting to the demo trading session…';
  late final MarketFeedService _marketFeed;
  late final DemoTradingService _demoTrading;
  final FeedServerLauncher _feedServerLauncher = FeedServerLauncher();
  Timer? _refreshTimer;
  Timer? _accountTimer;
  Timer? _orderReviewConfigTimer;
  String? _feedStartupError;

  @override
  void initState() {
    super.initState();
    _marketFeed = widget.marketFeedService ?? MarketFeedService();
    _demoTrading = widget.demoTradingService ?? DemoTradingService();
    _initializeMarketFeed();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshMarketFeed(),
    );
    _accountTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshDemoAccount(),
    );
  }

  Future<void> _initializeMarketFeed() async {
    final preferences = await SharedPreferences.getInstance();
    final savedUrl = preferences.getString('market_feed_url');
    final savedMode = preferences.getString('account_mode');
    if (!mounted) return;
    if (savedMode == 'demo' || savedMode == 'live') {
      _accountMode = savedMode!;
    }
    if (savedUrl != null && savedUrl.trim().isNotEmpty) {
      setState(() => _feedUrl = savedUrl.trim());
    }
    if (widget.marketFeedService == null &&
        _feedServerLauncher.supported &&
        _isLoopbackFeedUrl(_feedUrl)) {
      setState(() {
        _feedMessage = 'Starting the local Headway MT5 feed…';
      });
      try {
        await _feedServerLauncher.startIfNeeded(accountMode: _accountMode);
        _demoTrading.accessToken = _feedServerLauncher.accessToken;
        final localFeedUrl = _feedServerLauncher.baseUrl;
        if (localFeedUrl != null) {
          setState(() {
            _feedUrl = localFeedUrl;
            _feedStartupError = null;
          });
        }
        if (_demoTrading.accessToken != null) {
          await _syncOrderReviewConfiguration(enabled: false);
          await _syncBotConfiguration(enabled: false);
        }
      } on FeedServerStartException catch (error) {
        _feedStartupError = error.message;
      } on MarketFeedException catch (error) {
        _feedStartupError = error.message;
      }
    }
    await _refreshMarketFeed();
    if (mounted) await _refreshDemoAccount();
  }

  bool _isLoopbackFeedUrl(String value) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        uri.scheme == 'http' &&
        const {'127.0.0.1', 'localhost', '::1'}.contains(uri.host);
  }

  Future<void> _refreshDemoAccount() async {
    if (_loadingDemoAccount) return;
    final token = _demoTrading.accessToken;
    if (!_feedServerLauncher.supported) {
      if (!mounted) return;
      setState(() {
        _demoAccount = null;
        _demoAccountMessage =
            'Broker account connection requires the installed Windows desktop app; it is not available in the browser or mobile app.';
      });
      return;
    }
    if (token == null) {
      if (!mounted) return;
      setState(() {
        _demoAccount = null;
        _demoAccountMessage =
            _feedStartupError ??
            'The secure local MT5 service is not running in this app session. Start or retry the local service below.';
      });
      return;
    }
    _loadingDemoAccount = true;
    try {
      final account = await _demoTrading.fetchAccount(_feedUrl);
      if (!mounted) return;
      setState(() {
        _demoAccount = account;
        _demoAccountMessage =
            'Connected to the selected ${account.accountMode} MetaTrader account.';
      });
    } on MarketFeedException catch (error) {
      if (!mounted) return;
      setState(() {
        _demoAccount = null;
        _demoAccountMessage = error.message;
      });
    } finally {
      _loadingDemoAccount = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> _retryLocalFeed() async {
    if (!_feedServerLauncher.supported || _loadingDemoAccount) return;
    setState(() {
      _loadingDemoAccount = true;
      _demoAccountMessage = 'Starting the secure local MT5 service…';
    });
    var started = false;
    try {
      await _feedServerLauncher.startIfNeeded(accountMode: _accountMode);
      _demoTrading.accessToken = _feedServerLauncher.accessToken;
      final localFeedUrl = _feedServerLauncher.baseUrl;
      if (localFeedUrl != null) {
        setState(() => _feedUrl = localFeedUrl);
      }
      if (_demoTrading.accessToken != null) {
        await _syncOrderReviewConfiguration(enabled: false);
        await _syncBotConfiguration(enabled: false);
      }
      _feedStartupError = null;
      started = _demoTrading.accessToken != null;
    } on FeedServerStartException catch (error) {
      _feedStartupError = error.message;
    } on MarketFeedException catch (error) {
      _feedStartupError = error.message;
    } finally {
      if (mounted) {
        setState(() {
          _loadingDemoAccount = false;
          if (!started) {
            _demoAccount = null;
            _demoAccountMessage =
                _feedStartupError ??
                'The secure local MT5 service did not start.';
          }
        });
      }
    }
    if (started && mounted) {
      await _refreshMarketFeed();
      await _refreshDemoAccount();
    }
  }

  Future<void> _syncOrderReviewConfiguration({bool? enabled}) async {
    await _demoTrading.configureOrderReview(
      _feedUrl,
      accountMode: _accountMode,
      enabled: enabled ?? _orderReviewEnabled,
      riskPercent: _riskPerTrade.clamp(0.1, 0.5),
    );
  }

  Future<void> _syncBotConfiguration({
    required bool enabled,
    bool liveConfirmation = false,
    String? accountMode,
  }) async {
    await _demoTrading.configureBot(
      _feedUrl,
      accountMode: accountMode ?? _accountMode,
      enabled: enabled,
      liveConfirmation: liveConfirmation,
    );
  }

  Future<void> _selectAccountMode(String mode) async {
    if (mode == _accountMode) return;
    final previousMode = _accountMode;
    try {
      await _syncBotConfiguration(enabled: false, accountMode: mode);
      await _demoTrading.configureOrderReview(
        _feedUrl,
        accountMode: mode,
        enabled: false,
        riskPercent: _riskPerTrade.clamp(0.1, 0.5),
      );
      if (!mounted) return;
      setState(() {
        _accountMode = mode;
        _orderReviewEnabled = false;
        _botEnabled = false;
        _demoAccount = null;
        _demoAccountMessage = 'Checking the selected $mode MT5 account…';
      });
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('account_mode', mode);
      await _refreshMarketFeed();
      await _refreshDemoAccount();
    } on MarketFeedException catch (error) {
      if (!mounted) return;
      setState(() => _accountMode = previousMode);
      _notify(error.message);
    }
  }

  Future<void> _connectBrokerAccount({
    required String login,
    required String password,
    required String server,
  }) async {
    if (_accountMode == 'live') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Connect a real-money account?'),
          content: const Text(
            'This connects the selected live MT5 account to the app. Automated bot trading remains disabled until you separately enable it in Automation. Your password is sent only to the local MT5 service for sign-in and is not saved.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: _red),
              child: const Text('Connect Live account'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    if (_demoTrading.accessToken == null || !_feedServerLauncher.supported) {
      _notify(
        'Broker connection is available only from the Windows app with its local MT5 service.',
      );
      return;
    }

    setState(() {
      _loadingDemoAccount = true;
      _demoAccount = null;
      _demoAccountMessage = 'Connecting to the selected MT5 account…';
    });
    try {
      final account = await _demoTrading.connectAccount(
        _feedUrl,
        login: login,
        password: password,
        server: server,
        accountMode: _accountMode,
      );
      await (await SharedPreferences.getInstance()).setString(
        'account_mode',
        _accountMode,
      );
      if (!mounted) return;
      setState(() {
        _demoAccount = account;
        _demoAccountMessage =
            'Connected to the selected ${account.accountMode} MetaTrader account.';
        _orderReviewEnabled = false;
        _botEnabled = false;
      });
      _notify('Connected to ${account.server} as ${account.login}.');
      await _refreshMarketFeed();
    } on MarketFeedException catch (error) {
      if (!mounted) return;
      setState(() {
        _demoAccount = null;
        _demoAccountMessage = error.message;
      });
      _notify(error.message);
    } on Exception {
      if (!mounted) return;
      const message =
          'The account connection did not complete. Check that the local MT5 service is running and try again.';
      setState(() {
        _demoAccount = null;
        _demoAccountMessage = message;
      });
      _notify(message);
    } finally {
      _loadingDemoAccount = false;
      if (mounted) setState(() {});
    }
  }

  void _scheduleOrderReviewConfigurationUpdate() {
    _orderReviewConfigTimer?.cancel();
    _orderReviewConfigTimer = Timer(const Duration(milliseconds: 300), () async {
      if (!_orderReviewEnabled || _demoTrading.accessToken == null) return;
      try {
        await _syncOrderReviewConfiguration();
      } on MarketFeedException catch (error) {
        if (!mounted) return;
        setState(() => _orderReviewEnabled = false);
        _notify(
          'Order review was disabled because its settings could not be saved: ${error.message}',
        );
      }
    });
  }

  Future<void> _reviewDemoOrder(MarketSignal signal) async {
    if (_submittingDemoOrder) return;
    if (!_orderReviewEnabled) {
      _notify('Enable manual order review in Automation first.');
      return;
    }
    if (_demoTrading.accessToken == null) {
      _notify(
        'Trading is available only from the authorized Windows app session.',
      );
      return;
    }
    _submittingDemoOrder = true;
    try {
      final preview = await _demoTrading.previewOrder(
        _feedUrl,
        symbol: signal.pair,
        direction: signal.direction,
        riskPercent: _riskPerTrade.clamp(0.1, 0.5),
      );
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Review $_accountMode order'),
          content: Text(
            '${preview.direction} ${preview.symbol} · ${preview.volume} lots\n'
            'Current entry: ${preview.entry}\n'
            'Stop loss: ${preview.stopLoss}\n'
            'Take profit: ${preview.takeProfit}\n'
            'Estimated stop risk: ${preview.riskAmount.toStringAsFixed(2)} ${preview.currency} '
            '(${preview.riskPercent.toStringAsFixed(2)}% max)\n'
            'Market-mechanism score: ${preview.score}/${preview.scoreMax}\n\n'
            'This single market order will be sent only after your confirmation. Stop risk is an estimate, not guaranteed; price gaps and slippage can exceed it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: _amber),
              child: Text('Place $_accountMode order'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final result = await _demoTrading.executeOrder(
        _feedUrl,
        previewId: preview.id,
      );
      await _refreshDemoAccount();
      if (!mounted) return;
      _notify(
        '${_accountMode.toUpperCase()} ${result.direction} ${result.symbol} submitted · order ${result.order}.',
      );
    } on MarketFeedException catch (error) {
      if (!mounted) return;
      _notify(error.message);
    } finally {
      _submittingDemoOrder = false;
    }
  }

  Future<void> _refreshMarketFeed() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final snapshot = await _marketFeed.fetch(_feedUrl);
      if (!mounted) return;
      _feedStartupError = null;
      setState(() {
        _markets = snapshot.markets;
        _feedConnected = true;
        _feedMessage = 'Receiving live quotes from ${snapshot.source}.';
        _feedSource = snapshot.source;
        _lastFeedUpdate = snapshot.generatedAt;
        _selectedSignal = _selectedSignal.clamp(
          0,
          _markets.isEmpty ? 0 : _markets.length - 1,
        );
      });
    } on MarketFeedException catch (error) {
      if (!mounted) return;
      setState(() {
        _markets = [];
        _feedConnected = false;
        _feedMessage = _feedStartupError ?? error.message;
        _lastFeedUpdate = null;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _markets = [];
        _feedConnected = false;
        _feedMessage = _feedStartupError ?? 'Market feed error: $error';
        _lastFeedUpdate = null;
      });
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _saveFeedUrl(String value) async {
    final normalized = value.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        !uri.hasAuthority ||
        !const {'http', 'https'}.contains(uri.scheme)) {
      _notify('Enter a valid HTTP or HTTPS market-feed address.');
      return;
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString('market_feed_url', normalized);
    if (!mounted) return;
    setState(() {
      _feedUrl = normalized;
      _feedConnected = false;
      _feedMessage = 'Feed address saved. Checking the MT5 connection…';
    });
    await _refreshMarketFeed();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _accountTimer?.cancel();
    _orderReviewConfigTimer?.cancel();
    _marketFeed.close();
    _demoTrading.close();
    unawaited(_feedServerLauncher.stop());
    super.dispose();
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: _panelRaised,
          duration: const Duration(seconds: 8),
        ),
      );
  }

  void _selectPage(int index) {
    setState(() => _selectedIndex = index);
  }

  Future<void> _showMoreMenu() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _panel,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 3; i < _navItems.length; i++)
                ListTile(
                  leading: Icon(_navItems[i].icon, color: _lime),
                  title: Text(_navItems[i].label),
                  onTap: () {
                    Navigator.pop(context);
                    _selectPage(i);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 820;
        final page = _buildPage();
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                if (!isCompact) _buildSidebar(),
                Expanded(
                  child: Column(
                    children: [
                      _TopBar(
                        compact: isCompact,
                        narrow: constraints.maxWidth < 440,
                        pageTitle: _navItems[_selectedIndex].label,
                        feedConnected: _feedConnected,
                        onNotificationTap: () => _notify(
                          _notificationsEnabled
                              ? 'You are all caught up.'
                              : 'Notifications are paused.',
                        ),
                        onAccountTap: () => _selectPage(6),
                      ),
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: KeyedSubtree(
                            key: ValueKey(_selectedIndex),
                            child: page,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: isCompact
              ? NavigationBar(
                  selectedIndex: _selectedIndex > 3 ? 3 : _selectedIndex,
                  onDestinationSelected: (index) {
                    if (index == 3) {
                      _showMoreMenu();
                    } else {
                      _selectPage(index);
                    }
                  },
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.grid_view_rounded),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.bolt_rounded),
                      label: 'Signals',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.candlestick_chart_rounded),
                      label: 'Analysis',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.menu_rounded),
                      label: 'More',
                    ),
                  ],
                )
              : null,
        );
      },
    );
  }

  Widget _buildSidebar() {
    return Container(
      width: 228,
      decoration: BoxDecoration(
        color: _panel,
        border: Border(right: BorderSide(color: _line)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 25, 18, 26),
            child: _Brand(),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 0, 18, 10),
            child: _SectionLabel('WORKSPACE'),
          ),
          for (var i = 0; i < _navItems.length; i++)
            _SideNavItem(
              icon: _navItems[i].icon,
              label: _navItems[i].label,
              selected: _selectedIndex == i,
              onTap: () => _selectPage(i),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(14),
            child: _FeedNotice(
              compact: false,
              connected: _feedConnected,
              message: _feedMessage,
              lastUpdated: _lastFeedUpdate,
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 6, 20, 18),
            child: Text(
              'ARTIFACTS TERMINAL  ·  ${_accountMode.toUpperCase()}',
              style: TextStyle(color: _muted, fontSize: 9, letterSpacing: 1.2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPage() {
    switch (_selectedIndex) {
      case 1:
        return _SignalsPage(
          markets: _markets,
          feedConnected: _feedConnected,
          feedMessage: _feedMessage,
          onOpenAnalysis: (index) {
            setState(() {
              _selectedSignal = index;
              _selectedIndex = 2;
            });
          },
        );
      case 2:
        return _AnalysisPage(
          signal: _markets.isEmpty ? null : _markets[_selectedSignal],
          markets: _markets,
          onReviewOrder: _reviewDemoOrder,
          onPairChanged: (pair) {
            final index = _markets.indexWhere((market) => market.pair == pair);
            if (index >= 0) setState(() => _selectedSignal = index);
          },
          feedConnected: _feedConnected,
          feedMessage: _feedMessage,
          onRefresh: _refreshMarketFeed,
          timeframe: _selectedTimeframe,
          onTimeframeChanged: (value) =>
              setState(() => _selectedTimeframe = value),
        );
      case 3:
        return _PositionsPage(
          account: _demoAccount,
          message: _demoAccountMessage,
          loading: _loadingDemoAccount,
          markets: _markets,
          accountMode: _accountMode,
          eurusdTimeframe: _eurusdPositionsTimeframe,
          onEurusdTimeframeChanged: (value) =>
              setState(() => _eurusdPositionsTimeframe = value),
          usdcadTimeframe: _usdcadPositionsTimeframe,
          onUsdcadTimeframeChanged: (value) =>
              setState(() => _usdcadPositionsTimeframe = value),
          xauusdTimeframe: _xauusdPositionsTimeframe,
          onXauusdTimeframeChanged: (value) =>
              setState(() => _xauusdPositionsTimeframe = value),
          onOpenSettings: () => setState(() => _selectedIndex = 6),
          onRefresh: _refreshDemoAccount,
        );
      case 4:
        return _HistoryPage(
          mode: _accountMode,
          feedUrl: _feedUrl,
          tradingService: _demoTrading,
        );
      case 5:
        return _AutomationPage(
          enabled: _orderReviewEnabled,
          botEnabled: _botEnabled,
          riskPerTrade: _riskPerTrade,
          accountMode: _accountMode,
          onToggleBot: _toggleBot,
          onRiskChanged: (value) {
            setState(() => _riskPerTrade = value);
            _scheduleOrderReviewConfigurationUpdate();
          },
          onToggle: _toggleOrderReview,
        );
      case 6:
        return _SettingsPage(
          accountNumber: _demoAccount?.login.toString() ?? '—',
          server: _demoAccount?.server ?? 'MetaTrader 5',
          accountStatus: _demoAccountMessage,
          accountConnected: _demoAccount != null,
          accountConnecting: _loadingDemoAccount,
          canRetryFeed:
              _demoAccount == null &&
              _demoTrading.accessToken == null &&
              _feedServerLauncher.supported,
          onRetryFeed: _retryLocalFeed,
          environment: _accountMode,
          notificationsEnabled: _notificationsEnabled,
          lightTheme: widget.lightTheme,
          feedUrl: _feedUrl,
          feedConnected: _feedConnected,
          feedMessage: _feedMessage,
          feedSource: _feedSource,
          onNotificationsChanged: (value) =>
              setState(() => _notificationsEnabled = value),
          onLightThemeChanged: widget.onLightThemeChanged,
          onEnvironmentChanged: _selectAccountMode,
          onFeedUrlSaved: _saveFeedUrl,
          onRefresh: _refreshMarketFeed,
          onConnect: _connectBrokerAccount,
        );
      default:
        return _DashboardPage(
          markets: _markets,
          feedConnected: _feedConnected,
          feedMessage: _feedMessage,
          lastFeedUpdate: _lastFeedUpdate,
          onViewSignals: () => _selectPage(1),
          onRefresh: _refreshMarketFeed,
          onOpenAnalysis: (index) {
            setState(() {
              _selectedSignal = index;
              _selectedIndex = 2;
            });
          },
        );
    }
  }

  Future<void> _toggleOrderReview() async {
    final enabled = !_orderReviewEnabled;
    if (enabled && _accountMode == 'live') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Enable live order review?'),
          content: const Text(
            'This only enables individually reviewed live orders. Bot automation is controlled separately, and every manual order still requires your review and confirmation.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: _red),
              child: const Text('Enable live order review'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    try {
      await _syncOrderReviewConfiguration(enabled: enabled);
      if (!mounted) return;
      setState(() => _orderReviewEnabled = enabled);
      _notify(
        enabled
            ? 'Manual ${_accountMode.toUpperCase()} order review is enabled.'
            : 'Manual order review is disabled.',
      );
    } on MarketFeedException catch (error) {
      if (!mounted) return;
      _notify('Could not change order review: ${error.message}');
    }
  }

  Future<void> _toggleBot() async {
    final enabled = !_botEnabled;
    var liveConfirmation = false;
    if (enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            _accountMode == 'live'
                ? 'Enable live bot trading?'
                : 'Enable demo bot trading?',
          ),
          content: const Text(
            'The bot can place orders without per-order confirmation. With a confirmed liquidity sweep, scores 7/13 and 8/13 open two 0.10-lot scalping positions targeting \$4 each; these require an MT5 hedging account. Each order has a 0.5% risk cap, so combined risk can reach 1%. Scores 9/13 and higher keep the existing single-entry signal target and add-on behavior. XAUUSD is excluded. Keep the Windows app and MT5 terminal running.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: _accountMode == 'live' ? _red : _amber,
              ),
              child: Text(
                _accountMode == 'live' ? 'Enable live bot' : 'Enable demo bot',
              ),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      liveConfirmation = _accountMode == 'live';
    }

    try {
      await _syncBotConfiguration(
        enabled: enabled,
        liveConfirmation: liveConfirmation,
      );
      if (!mounted) return;
      setState(() => _botEnabled = enabled);
      _notify(
        enabled
            ? '${_accountMode.toUpperCase()} automated bot enabled.'
            : 'Bot disabled. Existing bot positions remain managed.',
      );
    } on MarketFeedException catch (error) {
      if (!mounted) return;
      _notify(
        'Could not ${enabled ? 'enable' : 'disable'} bot: ${error.message}',
      );
    }
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _lime,
            borderRadius: BorderRadius.circular(11),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            'assets/artifacts_icon_source.png',
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ARTIFACTS',
                style: TextStyle(
                  color: _white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.7,
                ),
              ),
              Text(
                'SIGNAL PRO',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _muted,
                  fontSize: 8,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.compact,
    required this.narrow,
    required this.pageTitle,
    required this.feedConnected,
    required this.onNotificationTap,
    required this.onAccountTap,
  });

  final bool compact;
  final bool narrow;
  final String pageTitle;
  final bool feedConnected;
  final VoidCallback onNotificationTap;
  final VoidCallback onAccountTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: EdgeInsets.symmetric(horizontal: compact ? 17 : 30),
      decoration: BoxDecoration(
        color: _background,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          if (compact) ...[
            Icon(Icons.show_chart_rounded, color: _lime, size: 22),
            const SizedBox(width: 10),
          ],
          Text(
            pageTitle,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          if (!compact) ...[
            const _MarketOpenBadge(),
            const SizedBox(width: 14),
          ],
          _FeedStatusBadge(connected: feedConnected),
          const SizedBox(width: 8),
          if (!narrow) ...[
            IconButton(
              tooltip: 'Notifications',
              onPressed: onNotificationTap,
              icon: const Icon(Icons.notifications_none_rounded),
              color: _muted,
            ),
            const SizedBox(width: 4),
            InkWell(
              onTap: onAccountTap,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _panelRaised,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.person_outline_rounded,
                  color: _lime,
                  size: 19,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MarketOpenBadge extends StatelessWidget {
  const _MarketOpenBadge();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.circle, size: 7, color: _green),
        SizedBox(width: 7),
        Text(
          'MARKET OPEN',
          style: TextStyle(
            color: _muted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
      ],
    );
  }
}

class _FeedStatusBadge extends StatelessWidget {
  const _FeedStatusBadge({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final tint = connected ? _green : _amber;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: tint.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 6, color: tint),
          const SizedBox(width: 6),
          Text(
            connected ? 'FEED LIVE' : 'FEED OFFLINE',
            style: TextStyle(
              color: tint,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _SideNavItem extends StatelessWidget {
  const _SideNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected ? _lime.withValues(alpha: 0.09) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Icon(icon, size: 18, color: selected ? _lime : _muted),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? _white : _muted,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (selected) ...[
                  const Spacer(),
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: _lime,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardPage extends StatelessWidget {
  const _DashboardPage({
    required this.markets,
    required this.feedConnected,
    required this.feedMessage,
    required this.lastFeedUpdate,
    required this.onViewSignals,
    required this.onRefresh,
    required this.onOpenAnalysis,
  });

  final List<MarketSignal> markets;
  final bool feedConnected;
  final String feedMessage;
  final DateTime? lastFeedUpdate;
  final VoidCallback onViewSignals;
  final VoidCallback onRefresh;
  final ValueChanged<int> onOpenAnalysis;

  @override
  Widget build(BuildContext context) {
    final setups = markets.where((market) => market.hasSignal).toList();
    final strongest = setups.isEmpty
        ? null
        : setups.reduce((a, b) => a.score >= b.score ? a : b);
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FeedNotice(
            compact: true,
            connected: feedConnected,
            message: feedMessage,
            lastUpdated: lastFeedUpdate,
          ),
          const SizedBox(height: 21),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 720;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          feedConnected
                              ? 'Connected to Headway MT5 demo'
                              : 'Waiting for live broker data',
                          style: TextStyle(
                            color: _muted,
                            fontSize: compact ? 12 : 13,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Live market overview',
                          style: TextStyle(
                            fontSize: compact ? 22 : 27,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 17),
                    label: const Text('Refresh feed'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _lime,
                      foregroundColor: _background,
                      padding: EdgeInsets.symmetric(
                        horizontal: compact ? 11 : 16,
                        vertical: 13,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth > 1150
                  ? 4
                  : constraints.maxWidth > 650
                  ? 2
                  : 1;
              final cardWidth =
                  (constraints.maxWidth - (columns - 1) * 12) / columns;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: cardWidth,
                    child: _MetricCard(
                      label: 'LIVE PAIRS',
                      value: feedConnected ? '${markets.length}' : '—',
                      detail: 'Local MetaTrader 5 feed',
                      icon: Icons.account_balance_wallet_outlined,
                      color: _blue,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _MetricCard(
                      label: 'MARKET SIGNALS',
                      value: '${setups.length}',
                      detail: 'Medium and high setups · 7+/13',
                      icon: Icons.trending_up_rounded,
                      color: _green,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _MetricCard(
                      label: 'STRONGEST SIGNAL',
                      value: strongest == null
                          ? 'WAIT'
                          : '${strongest.pair} ${strongest.direction}',
                      detail: strongest == null
                          ? 'No signal at 7+/13'
                          : 'Confluence ${strongest.score}/${strongest.scoreMax}',
                      icon: Icons.swap_horiz_rounded,
                      color: _amber,
                    ),
                  ),
                  SizedBox(
                    width: cardWidth,
                    child: _MetricCard(
                      label: 'LAST FEED UPDATE',
                      value: lastFeedUpdate == null
                          ? '—'
                          : _timeLabel(lastFeedUpdate!),
                      detail: feedConnected
                          ? 'Auto refresh · 5 seconds'
                          : 'Feed disconnected',
                      icon: Icons.show_chart_rounded,
                      color: _lime,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          if (feedConnected && markets.isNotEmpty)
            _LiveOverviewCharts(
              markets: markets,
              onOpenAnalysis: onOpenAnalysis,
            )
          else
            _EmptyFeedPanel(message: feedMessage, onRefresh: onRefresh),
          const SizedBox(height: 14),
          _Panel(
            child: Column(
              children: [
                _PanelHeading(
                  title: 'Live market watch',
                  subtitle: feedConnected
                      ? 'Broker quotes · 7/13+ market-mechanism signals'
                      : 'No broker prices are currently available',
                  actionLabel: 'View all',
                  onAction: onViewSignals,
                ),
                const SizedBox(height: 8),
                if (markets.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No live quotes. Check the MT5 feed connection.',
                      style: TextStyle(color: _muted, fontSize: 10),
                    ),
                  )
                else
                  for (var i = 0; i < markets.length; i++)
                    _SignalRow(
                      signal: markets[i],
                      onTap: () => onOpenAnalysis(i),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _Panel(
            child: Text(
              'Signals are computed from closed Headway MT5 candles. WAIT '
              'means the setup score is below 7/13. MEDIUM signals score 7-9 '
              'and STRONG signals 10-13; confluence is not a probability of profit.',
              style: TextStyle(color: _muted, fontSize: 10, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _PageScroll extends StatelessWidget {
  const _PageScroll({
    required this.child,
    this.topPadding = 18,
    this.fillViewport = false,
  });

  final Widget child;
  final double topPadding;
  final bool fillViewport;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          constraints.maxWidth < 700 ? 15 : 28,
          topPadding,
          constraints.maxWidth < 700 ? 15 : 28,
          26,
        ),
        child: ConstrainedBox(
          constraints: fillViewport
              ? BoxConstraints(
                  minHeight: constraints.maxHeight - topPadding - 26,
                )
              : const BoxConstraints(),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1450),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _FeedNotice extends StatelessWidget {
  const _FeedNotice({
    required this.compact,
    required this.connected,
    required this.message,
    this.lastUpdated,
  });

  final bool compact;
  final bool connected;
  final String message;
  final DateTime? lastUpdated;

  @override
  Widget build(BuildContext context) {
    final color = connected ? _green : _amber;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 10,
        vertical: compact ? 10 : 12,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          Icon(
            connected ? Icons.wifi_tethering_rounded : Icons.wifi_off_rounded,
            color: color,
            size: 17,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              '${compact ? '' : 'ARTIFACTS · '}${connected ? 'LIVE MT5 FEED' : 'MT5 FEED OFFLINE'} · '
              '$message${lastUpdated == null ? '' : ' Updated ${_timeLabel(lastUpdated!)}.'}',
              style: TextStyle(
                color: connected ? _green : const Color(0xFFE7C896),
                fontSize: 10,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TradingNotice extends StatelessWidget {
  const _TradingNotice({required this.mode});

  final String mode;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: _amber.withValues(alpha: 0.07),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _amber.withValues(alpha: 0.16)),
    ),
    child: Row(
      children: [
        Icon(Icons.lock_outline_rounded, color: _amber, size: 16),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            'MT5 ${mode.toUpperCase()} ACCOUNT · Orders are submitted only after you review and confirm them.',
            style: TextStyle(color: _amber, fontSize: 9, height: 1.4),
          ),
        ),
      ],
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                label,
                style: TextStyle(
                  color: _muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const Spacer(),
              Icon(icon, color: color, size: 16),
            ],
          ),
          const SizedBox(height: 14),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: _white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(detail, style: TextStyle(color: _muted, fontSize: 10)),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(18)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
      ),
      child: child,
    );
  }
}

class _PanelHeading extends StatelessWidget {
  const _PanelHeading({
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: TextStyle(color: _muted, fontSize: 10)),
              ],
            ],
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: _lime,
              textStyle: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

class _LiveOverviewCharts extends StatelessWidget {
  const _LiveOverviewCharts({
    required this.markets,
    required this.onOpenAnalysis,
  });

  final List<MarketSignal> markets;
  final ValueChanged<int> onOpenAnalysis;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelHeading(
          title: 'All pair charts · 1-hour candles',
          subtitle:
              'Closed-candle charts with the current scored market signal',
          actionLabel: '${markets.length} markets',
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1100
                ? 3
                : constraints.maxWidth >= 650
                ? 2
                : 1;
            final spacing = 12.0;
            final width =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (var index = 0; index < markets.length; index++)
                  SizedBox(
                    width: width,
                    child: _OverviewPairChart(
                      signal: markets[index],
                      onTap: () => onOpenAnalysis(index),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _OverviewPairChart extends StatelessWidget {
  const _OverviewPairChart({required this.signal, required this.onTap});

  final MarketSignal signal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final directionColor = signal.direction == 'BUY'
        ? _green
        : signal.direction == 'SELL'
        ? _red
        : _blue;
    final candles = signal.candles['1h'] ?? const <MarketCandle>[];
    return _Panel(
      padding: const EdgeInsets.all(13),
      child: SizedBox(
        height: 230,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              key: ValueKey('overview-chart-${signal.pair}'),
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      signal.pair,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _Tag(label: signal.direction, color: directionColor),
                  const SizedBox(width: 7),
                  Text(
                    signal.hasSignal
                        ? '${signal.score}/${signal.scoreMax}'
                        : 'WAIT',
                    style: TextStyle(
                      color: directionColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '${_formatQuote(signal.bid, signal.pair)} / '
              '${_formatQuote(signal.ask, signal.pair)}  ·  '
              'H4 ${signal.timeframes['4h'] ?? '—'}  ·  '
              'H1 ${signal.timeframes['1h'] ?? '—'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _muted, fontSize: 8),
            ),
            const SizedBox(height: 9),
            Expanded(
              child: CustomPaint(
                key: ValueKey('overview-candles-${signal.pair}'),
                painter: _MarketCandlestickPainter(
                  candles: candles,
                  bid: signal.bid,
                  patterns: signal.chartPatterns
                      .where((pattern) => pattern.timeframe == '1h')
                      .toList(growable: false),
                ),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                Expanded(
                  child: Text(
                    signal.setup,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _muted, fontSize: 8),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${candles.length} bars · ${signal.time}',
                  style: TextStyle(color: _muted, fontSize: 8),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyFeedPanel extends StatelessWidget {
  const _EmptyFeedPanel({required this.message, required this.onRefresh});

  final String message;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: _amber, size: 23),
          const SizedBox(width: 12),
          Expanded(
            child: Text(message, style: TextStyle(color: _muted, fontSize: 10)),
          ),
          TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded, size: 15),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

String _timeLabel(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';

String _formatQuote(double value, String symbol) => value.toStringAsFixed(
  symbol.endsWith('JPY')
      ? 3
      : symbol == 'XAUUSD' || symbol == 'BTCUSD' || symbol == 'NASDAQ-100'
      ? 2
      : 5,
);

class _AxisLabel extends StatelessWidget {
  const _AxisLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) =>
      Text(label, style: TextStyle(color: _muted, fontSize: 9));
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(color: _muted, fontSize: 10)),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _SignalRow extends StatelessWidget {
  const _SignalRow({required this.signal, required this.onTap});

  final MarketSignal signal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final buy = signal.direction == 'BUY';
    final sell = signal.direction == 'SELL';
    final tint = buy
        ? _green
        : sell
        ? _red
        : _blue;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                buy
                    ? Icons.north_east_rounded
                    : sell
                    ? Icons.south_east_rounded
                    : Icons.remove_rounded,
                color: tint,
                size: 17,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    signal.pair,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    signal.setup,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: _muted, fontSize: 9),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            _Tag(label: signal.direction, color: tint),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  signal.hasSignal
                      ? '${signal.score}/${signal.scoreMax}'
                      : 'NO SETUP',
                  style: TextStyle(
                    color: signal.hasSignal ? tint : _muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_formatQuote(signal.bid, signal.pair)} / '
                  '${_formatQuote(signal.ask, signal.pair)}',
                  style: TextStyle(color: _muted, fontSize: 8),
                ),
              ],
            ),
            if (MediaQuery.sizeOf(context).width > 600) ...[
              const SizedBox(width: 12),
              Text(signal.time, style: TextStyle(color: _muted, fontSize: 9)),
            ],
            const SizedBox(width: 3),
            Icon(Icons.chevron_right_rounded, color: _muted, size: 17),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SignalsPage extends StatefulWidget {
  const _SignalsPage({
    required this.markets,
    required this.feedConnected,
    required this.feedMessage,
    required this.onOpenAnalysis,
  });

  final List<MarketSignal> markets;
  final bool feedConnected;
  final String feedMessage;
  final ValueChanged<int> onOpenAnalysis;

  @override
  State<_SignalsPage> createState() => _SignalsPageState();
}

class _SignalsPageState extends State<_SignalsPage> {
  String _filter = 'All';
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final visible = widget.markets.indexed.where((item) {
      final signal = item.$2;
      final directionMatch =
          _filter == 'All' || signal.direction == _filter.toUpperCase();
      final searchMatch = signal.pair.toLowerCase().contains(
        _search.toLowerCase(),
      );
      return directionMatch && searchMatch;
    }).toList();

    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FeedNotice(
            compact: true,
            connected: widget.feedConnected,
            message: widget.feedMessage,
          ),
          const SizedBox(height: 21),
          const Text(
            'Signal feed',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            'SMC-only setups · 4H structure bias with 1H confirmation',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
          const SizedBox(height: 17),
          LayoutBuilder(
            builder: (context, constraints) {
              final chips = Wrap(
                spacing: 7,
                children: [
                  for (final filter in ['All', 'Buy', 'Sell'])
                    ChoiceChip(
                      label: Text(filter),
                      selected: _filter == filter,
                      onSelected: (_) => setState(() => _filter = filter),
                      selectedColor: _lime.withValues(alpha: 0.15),
                      side: BorderSide(
                        color: _filter == filter ? _lime : _line,
                      ),
                      labelStyle: TextStyle(
                        color: _filter == filter ? _lime : _muted,
                        fontSize: 10,
                      ),
                    ),
                ],
              );
              final search = SizedBox(
                width: constraints.maxWidth > 600 ? 245 : constraints.maxWidth,
                child: TextField(
                  onChanged: (value) => setState(() => _search = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                    hintText: 'Search pair',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              );
              if (constraints.maxWidth < 580) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [chips, const SizedBox(height: 9), search],
                );
              }
              return Row(
                children: [
                  Expanded(child: chips),
                  search,
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          _Panel(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Column(
              children: [
                for (final item in visible)
                  _SignalDetailRow(
                    signal: item.$2,
                    onTap: () => widget.onOpenAnalysis(item.$1),
                  ),
                if (visible.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(28),
                    child: Text(
                      'No signals match your filters.',
                      style: TextStyle(color: _muted, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const _ScoringGuide(),
        ],
      ),
    );
  }
}

class _SignalDetailRow extends StatelessWidget {
  const _SignalDetailRow({required this.signal, required this.onTap});

  final MarketSignal signal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = signal.direction == 'BUY'
        ? _green
        : signal.direction == 'SELL'
        ? _red
        : _blue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    signal.direction == 'BUY'
                        ? Icons.north_east_rounded
                        : signal.direction == 'SELL'
                        ? Icons.south_east_rounded
                        : Icons.remove_rounded,
                    color: color,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        signal.pair,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${signal.setup} · ${_formatQuote(signal.bid, signal.pair)} / ${_formatQuote(signal.ask, signal.pair)}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _muted, fontSize: 9),
                      ),
                    ],
                  ),
                ),
                if (MediaQuery.sizeOf(context).width > 700) ...[
                  _PriceColumn(label: 'ENTRY', value: signal.entry),
                  const SizedBox(width: 16),
                  _PriceColumn(label: 'STOP', value: signal.stop),
                  const SizedBox(width: 16),
                  _PriceColumn(label: 'TARGET', value: signal.target),
                  const SizedBox(width: 16),
                ],
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      signal.hasSignal
                          ? '${signal.score}/${signal.scoreMax}'
                          : signal.score == 0
                          ? 'WAIT'
                          : 'WAIT · ${signal.score}/${signal.scoreMax}',
                      style: TextStyle(
                        color: signal.hasSignal
                            ? signal.status == 'STRONG'
                                  ? _lime
                                  : _amber
                            : _blue,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'QUALITY',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 8,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 7),
                Icon(Icons.chevron_right_rounded, color: _muted, size: 17),
              ],
            ),
          ),
        ),
        _SignalSetupProgress(signal: signal),
        Divider(height: 1, color: _line),
      ],
    );
  }
}

class _SignalSetupProgress extends StatelessWidget {
  const _SignalSetupProgress({required this.signal});

  final MarketSignal signal;

  static const _steps = <({String key, String label, int weight})>[
    (key: 'h4_trend_alignment', label: '4H trend', weight: 2),
    (key: 'h1_structure_alignment', label: '1H structure', weight: 2),
    (key: 'liquidity_identified', label: 'Nearby liquidity', weight: 2),
    (key: 'liquidity_sweep', label: 'Liquidity sweep', weight: 2),
    (key: 'structure_shift', label: '15M BOS / CHoCH', weight: 2),
    (key: 'displacement', label: 'Displacement', weight: 1),
    (key: 'entry_zone', label: 'Entry zone', weight: 1),
    (key: 'risk_reward', label: 'Risk / reward', weight: 1),
  ];

  @override
  Widget build(BuildContext context) {
    final confirmedCount = _steps
        .where((step) => signal.criteria[step.key] == true)
        .length;
    final quoteIsStale = signal.status == 'STALE';

    return Padding(
      padding: const EdgeInsets.only(left: 50, right: 12, bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Market setup · ${signal.score}/${signal.scoreMax} points · $confirmedCount/${_steps.length} checks',
                  style: TextStyle(
                    color: _white,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                quoteIsStale
                    ? 'STALE QUOTE'
                    : signal.hasSignal
                    ? '${signal.status} SIGNAL'
                    : 'WAITING',
                style: TextStyle(
                  color: quoteIsStale
                      ? _amber
                      : signal.hasSignal
                      ? _lime
                      : _muted,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (signal.score / signal.scoreMax)
                  .clamp(0.0, 1.0)
                  .toDouble(),
              minHeight: 5,
              backgroundColor: _line,
              color: signal.hasSignal ? _lime : _amber,
            ),
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final step in _steps)
                _SignalStepChip(
                  label: step.label,
                  weight: step.weight,
                  confirmed: signal.criteria[step.key] == true,
                ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            quoteIsStale
                ? 'Waiting for a fresh broker quote; setup conditions are not current.'
                : 'Checks reflect the latest closed-candle analysis. Score is rule alignment, not win probability.',
            style: TextStyle(color: _muted, fontSize: 9, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _SignalStepChip extends StatelessWidget {
  const _SignalStepChip({
    required this.label,
    required this.weight,
    required this.confirmed,
  });

  final String label;
  final int weight;
  final bool confirmed;

  @override
  Widget build(BuildContext context) {
    final color = confirmed ? _green : _muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: confirmed ? _green.withValues(alpha: 0.07) : _background,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(
          color: confirmed ? _green.withValues(alpha: 0.3) : _line,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            confirmed
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontSize: 8)),
          const SizedBox(width: 5),
          Text(
            '+$weight',
            style: TextStyle(
              color: confirmed ? _lime : _muted,
              fontSize: 8,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceColumn extends StatelessWidget {
  const _PriceColumn({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(color: _muted, fontSize: 8, letterSpacing: 0.5),
        ),
      ],
    );
  }
}

class _ScoringGuide extends StatelessWidget {
  const _ScoringGuide();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelHeading(
            title: 'SMC score breakdown',
            subtitle: 'Criteria and weights used by the signal engine',
          ),
          const SizedBox(height: 13),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ScorePill('4H structure', '+25'),
              _ScorePill('1H liquidity sweep', '+25'),
              _ScorePill('1H MSS / BOS', '+25'),
              _ScorePill('Mitigated order block', '+12'),
              _ScorePill('Mitigated FVG', '+13'),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Scores describe rule alignment only; they are not a probability of profit.',
            style: TextStyle(color: _muted, fontSize: 9),
          ),
        ],
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill(this.label, this.score);

  final String label;
  final String score;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _line),
      ),
      child: Text.rich(
        TextSpan(
          text: '$label  ',
          style: TextStyle(color: _muted, fontSize: 9),
          children: [
            TextSpan(
              text: score,
              style: TextStyle(color: _lime, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalysisPage extends StatelessWidget {
  const _AnalysisPage({
    required this.signal,
    required this.markets,
    required this.onReviewOrder,
    required this.onPairChanged,
    required this.feedConnected,
    required this.feedMessage,
    required this.onRefresh,
    required this.timeframe,
    required this.onTimeframeChanged,
  });

  final MarketSignal? signal;
  final List<MarketSignal> markets;
  final Future<void> Function(MarketSignal) onReviewOrder;
  final ValueChanged<String> onPairChanged;
  final bool feedConnected;
  final String feedMessage;
  final VoidCallback onRefresh;
  final String timeframe;
  final ValueChanged<String> onTimeframeChanged;

  @override
  Widget build(BuildContext context) {
    final market = signal;
    if (market == null) {
      return _PageScroll(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FeedNotice(
              compact: true,
              connected: feedConnected,
              message: feedMessage,
            ),
            const SizedBox(height: 18),
            _EmptyFeedPanel(message: feedMessage, onRefresh: onRefresh),
          ],
        ),
      );
    }
    final tint = market.direction == 'BUY'
        ? _green
        : market.direction == 'SELL'
        ? _red
        : _blue;
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FeedNotice(
            compact: true,
            connected: feedConnected,
            message: feedMessage,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Chart analysis',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    DropdownButton<String>(
                      key: const ValueKey('analysis-pair-selector'),
                      value: market.pair,
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      items: [
                        for (final item in markets)
                          DropdownMenuItem(
                            value: item.pair,
                            child: Text(item.pair),
                          ),
                      ],
                      onChanged: (pair) {
                        if (pair != null) onPairChanged(pair);
                      },
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Choose a market to inspect its live MT5 chart and patterns.',
                      style: TextStyle(color: _muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              _Tag(label: market.direction, color: tint),
              const SizedBox(width: 8),
              Text(
                market.hasSignal
                    ? '${market.score}/${market.scoreMax}'
                    : 'NO SETUP',
                style: TextStyle(
                  color: market.hasSignal
                      ? market.status == 'STRONG'
                            ? _lime
                            : _amber
                      : _blue,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 840;
              final chart = _ChartPanel(
                signal: market,
                timeframe: timeframe,
                onTimeframeChanged: onTimeframeChanged,
                height: stacked ? 335 : 460,
              );
              final details = _AnalysisDetails(
                signal: market,
                timeframe: timeframe,
              );
              if (stacked) {
                return Column(
                  children: [chart, const SizedBox(height: 13), details],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: chart),
                  const SizedBox(width: 13),
                  Expanded(flex: 4, child: details),
                ],
              );
            },
          ),
          if (market.hasSignal) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => onReviewOrder(market),
                icon: const Icon(Icons.fact_check_outlined, size: 16),
                label: const Text('Review market signal'),
              ),
            ),
          ],
          const SizedBox(height: 13),
          const _TimeframeRoadmap(),
        ],
      ),
    );
  }
}

class _ChartPanel extends StatelessWidget {
  const _ChartPanel({
    required this.signal,
    required this.timeframe,
    required this.onTimeframeChanged,
    required this.height,
    this.timeframeKeyPrefix = 'chart',
    this.showPositionTimeframes = false,
  });

  final MarketSignal signal;
  final String timeframe;
  final ValueChanged<String> onTimeframeChanged;
  final double height;
  final String timeframeKeyPrefix;
  final bool showPositionTimeframes;

  @override
  Widget build(BuildContext context) {
    final frame = timeframe.toLowerCase();
    final candles = signal.candles[frame] ?? const <MarketCandle>[];
    return _Panel(
      child: SizedBox(
        height: height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${signal.pair} · ${_formatQuote(signal.bid, signal.pair)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                for (final frame
                    in showPositionTimeframes ? ['15M', '5M'] : ['1H', '4H'])
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: InkWell(
                      onTap: () => onTimeframeChanged(frame),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: timeframe == frame
                              ? _lime.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          frame,
                          key: ValueKey('$timeframeKeyPrefix-timeframe-$frame'),
                          style: TextStyle(
                            color: timeframe == frame ? _lime : _muted,
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: CustomPaint(
                painter: _MarketCandlestickPainter(
                  candles: candles,
                  bid: signal.bid,
                  patterns: signal.chartPatterns
                      .where((pattern) => pattern.timeframe == frame)
                      .toList(growable: false),
                ),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 9),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _AxisLabel('${candles.length} closed bars'),
                _AxisLabel('Updated ${signal.time}'),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 13,
              runSpacing: 7,
              children: showPositionTimeframes
                  ? [
                      _LegendDot(color: _green, label: 'Bullish candle'),
                      _LegendDot(color: _red, label: 'Bearish candle'),
                      _LegendDot(color: _blue, label: 'Current bid'),
                    ]
                  : [
                      _LegendDot(color: _green, label: 'Bullish candle'),
                      _LegendDot(color: _red, label: 'Bearish candle'),
                      _LegendDot(color: _blue, label: 'Current bid'),
                      _LegendDot(color: _amber, label: 'Liquidity sweep'),
                      _LegendDot(color: Color(0xFF78A9FF), label: 'FVG'),
                      _LegendDot(
                        color: Color(0xFFC2F970),
                        label: 'Order block',
                      ),
                      _LegendDot(color: Color(0xFF49D6A0), label: 'Retest'),
                      _LegendDot(color: _white, label: 'Suggested entry'),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketCandlestickPainter extends CustomPainter {
  _MarketCandlestickPainter({
    required this.candles,
    required this.bid,
    required this.patterns,
  });

  final List<MarketCandle> candles;
  final double? bid;
  final List<ChartPattern> patterns;

  @override
  void paint(Canvas canvas, Size size) {
    if (candles.isEmpty || size.isEmpty) return;
    for (var i = 0; i < 5; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        Paint()
          ..color = _line
          ..strokeWidth = 1,
      );
    }

    final visible = candles.length > 80
        ? candles.sublist(candles.length - 80)
        : candles;
    final low = visible.map((candle) => candle.low).reduce(min);
    final high = visible.map((candle) => candle.high).reduce(max);
    final range = max(high - low, 0.0000001);
    final padding = range * 0.08;
    final chartLow = low - padding;
    final chartHigh = high + padding;
    final chartRange = chartHigh - chartLow;
    double y(double price) => (chartHigh - price) / chartRange * size.height;
    final slotWidth = size.width / visible.length;
    final bodyWidth = min(slotWidth * 0.64, 12.0);
    final firstTime = visible.first.time.millisecondsSinceEpoch;
    final lastTime = visible.last.time.millisecondsSinceEpoch;
    final timeRange = max(lastTime - firstTime, 1);
    double x(DateTime time) =>
        ((time.millisecondsSinceEpoch - firstTime) / timeRange).clamp(
          0.0,
          1.0,
        ) *
        size.width;

    for (final pattern in patterns) {
      final color = switch (pattern.type) {
        'liquidity_sweep' => _amber,
        'pullback' => _lime,
        'breakout_retest' => _green,
        'range_edge' => const Color(0xFF49D6A0),
        'fvg' => _blue,
        'order_block' => _lime,
        'retest' => _green,
        'entry' => _white,
        _ => _muted,
      };
      final startX = x(pattern.startTime);
      final endX = max(x(pattern.endTime), startX + 4);
      final upperY = y(pattern.high);
      final lowerY = y(pattern.low);
      if (pattern.type == 'fvg' || pattern.type == 'order_block') {
        final zonePaint = Paint()
          ..color = color.withValues(alpha: 0.8)
          ..strokeWidth = 1.2;
        canvas.drawLine(
          Offset(startX, upperY),
          Offset(endX, upperY),
          zonePaint,
        );
        if ((upperY - lowerY).abs() > 0.5) {
          canvas.drawLine(
            Offset(startX, lowerY),
            Offset(endX, lowerY),
            zonePaint,
          );
        }
      } else if (pattern.level != null) {
        final levelY = y(pattern.level!);
        canvas.drawLine(
          Offset(startX, levelY),
          Offset(size.width, levelY),
          Paint()
            ..color = color.withValues(alpha: 0.8)
            ..strokeWidth = 1.2,
        );
        if (pattern.type == 'retest' || pattern.type == 'entry') {
          canvas.drawCircle(
            Offset(startX, levelY),
            pattern.type == 'entry' ? 3 : 4,
            Paint()
              ..color = color
              ..style = PaintingStyle.fill,
          );
        }
      }
    }

    for (var i = 0; i < visible.length; i++) {
      final candle = visible[i];
      final x = slotWidth * i + slotWidth / 2;
      final open = y(candle.open);
      final close = y(candle.close);
      final candleHigh = y(candle.high);
      final candleLow = y(candle.low);
      final color = candle.close >= candle.open ? _green : _red;
      final candlePaint = Paint()
        ..color = color
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x, candleHigh), Offset(x, candleLow), candlePaint);
      final top = min(open, close);
      final bottom = max(open, close);
      canvas.drawRect(
        Rect.fromLTRB(
          x - bodyWidth / 2,
          top,
          x + bodyWidth / 2,
          max(bottom, top + 1.5),
        ),
        Paint()..color = color.withValues(alpha: 0.86),
      );
    }

    if (bid != null) {
      final bidY = y(bid!);
      canvas.drawLine(
        Offset(0, bidY),
        Offset(size.width, bidY),
        Paint()
          ..color = _blue
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MarketCandlestickPainter oldDelegate) =>
      oldDelegate.bid != bid ||
      oldDelegate.candles != candles ||
      oldDelegate.patterns != patterns;
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: _muted, fontSize: 8)),
      ],
    );
  }
}

class _AnalysisDetails extends StatelessWidget {
  const _AnalysisDetails({required this.signal, required this.timeframe});

  final MarketSignal signal;
  final String timeframe;

  @override
  Widget build(BuildContext context) {
    final directionColor = signal.direction == 'BUY'
        ? _green
        : signal.direction == 'SELL'
        ? _red
        : _blue;
    final quoteFresh =
        signal.quoteAgeSeconds >= 0 && signal.quoteAgeSeconds <= 30;
    final quoteAge = signal.quoteAgeSeconds < 0
        ? '${-signal.quoteAgeSeconds}s ahead · check terminal clock'
        : '${signal.time} · ${signal.quoteAgeSeconds}s old';
    ChartPattern? suggestedSetup;
    for (final pattern in signal.chartPatterns) {
      if ((pattern.type == 'fvg' || pattern.type == 'order_block') &&
          pattern.timeframe == timeframe.toLowerCase() &&
          pattern.entry != null &&
          (suggestedSetup == null ||
              pattern.startTime.isAfter(suggestedSetup.startTime))) {
        suggestedSetup = pattern;
      }
    }
    Widget patternStatus(String type, String label) {
      ChartPattern? found;
      for (final pattern in signal.chartPatterns) {
        if (pattern.type == type &&
            pattern.timeframe == timeframe.toLowerCase() &&
            (found == null || pattern.startTime.isAfter(found.startTime))) {
          found = pattern;
        }
      }
      if (found == null) {
        return _AnalysisCheck(label, 'Not detected', _muted);
      }
      final price = found.level ?? found.high;
      final detail = type == 'fvg' || type == 'order_block'
          ? '${found.direction} · ${_formatQuote(found.low, signal.pair)}-${_formatQuote(found.high, signal.pair)}'
          : '${found.direction} · ${_formatQuote(price, signal.pair)}';
      final color = switch (type) {
        'liquidity_sweep' => _amber,
        'fvg' => _blue,
        'order_block' => _lime,
        'retest' => _green,
        _ => _muted,
      };
      return _AnalysisCheck(label, detail, color);
    }

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelHeading(
            title: 'Chart patterns',
            subtitle: 'Detected on the selected timeframe',
          ),
          const SizedBox(height: 8),
          _AnalysisCheck(
            'Live broker quote',
            quoteAge,
            quoteFresh ? _green : _amber,
          ),
          const SizedBox(height: 16),
          Center(
            child: SizedBox(
              width: 100,
              height: 100,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: signal.score / signal.scoreMax,
                      strokeWidth: 7,
                      backgroundColor: _line,
                      color: signal.status == 'STRONG' ? _lime : _amber,
                      strokeCap: StrokeCap.round,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${signal.score}',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'POINTS /13',
                        style: TextStyle(color: _muted, fontSize: 8),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          patternStatus('liquidity_sweep', 'Liquidity sweep'),
          patternStatus('fvg', 'Fair value gap'),
          patternStatus('order_block', 'Order block'),
          patternStatus('retest', 'Structure retest'),
          Divider(height: 16, color: _line),
          Text(
            'Market-mechanism scorecard · ${signal.score}/${signal.scoreMax}',
            style: TextStyle(
              color: _white,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 9),
          _AnalysisCheck(
            '4H trend alignment',
            signal.timeframes['4h'] ?? 'WAIT',
            signal.timeframes['4h'] == 'BUY'
                ? _green
                : signal.timeframes['4h'] == 'SELL'
                ? _red
                : _muted,
          ),
          _AnalysisCheck(
            '1H structure alignment',
            signal.criteria['h1_structure_alignment'] == true
                ? 'Confirmed'
                : 'Waiting',
            signal.criteria['h1_structure_alignment'] == true ? _green : _muted,
          ),
          _AnalysisCheck(
            'Nearby liquidity level',
            signal.criteria['liquidity_identified'] == true
                ? 'Identified'
                : 'Waiting',
            signal.criteria['liquidity_identified'] == true ? _green : _muted,
          ),
          _AnalysisCheck(
            'Liquidity sweep',
            signal.criteria['liquidity_sweep'] == true
                ? '${signal.direction} · Confirmed'
                : 'Waiting',
            signal.criteria['liquidity_sweep'] == true &&
                    signal.direction == 'BUY'
                ? _green
                : signal.criteria['liquidity_sweep'] == true &&
                      signal.direction == 'SELL'
                ? _red
                : _muted,
          ),
          _AnalysisCheck(
            '15M BOS / CHoCH after sweep',
            signal.criteria['structure_shift'] == true
                ? 'Confirmed'
                : 'Waiting',
            signal.criteria['structure_shift'] == true ? _green : _muted,
          ),
          _AnalysisCheck(
            'Directional displacement',
            signal.criteria['displacement'] == true ? 'Confirmed' : 'Waiting',
            signal.criteria['displacement'] == true ? _green : _muted,
          ),
          _AnalysisCheck(
            'Entry zone mitigation',
            signal.criteria['entry_zone'] == true ? 'Confirmed' : 'Waiting',
            signal.criteria['entry_zone'] == true ? _green : _muted,
          ),
          _AnalysisCheck(
            'Valid stop and 2:1 risk/reward',
            signal.criteria['risk_reward'] == true ? 'Confirmed' : 'Waiting',
            signal.criteria['risk_reward'] == true ? _green : _muted,
          ),
          _AnalysisCheck(
            'Order block confluence',
            signal.criteria['order_block'] == true ? 'Confirmed' : 'Waiting',
            signal.criteria['order_block'] == true ? _green : _muted,
          ),
          _AnalysisCheck(
            'Fair value gap confluence',
            signal.criteria['fvg'] == true ? 'Confirmed' : 'Waiting',
            signal.criteria['fvg'] == true ? _green : _muted,
          ),
          if (signal.criteria['order_block'] != true &&
              signal.criteria['fvg'] != true)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'A medium signal can appear before zone mitigation; review its score and remaining conditions.',
                style: TextStyle(color: _muted, fontSize: 8),
              ),
            ),
          if (suggestedSetup != null) ...[
            Divider(height: 22, color: _line),
            _InfoLine(
              label: 'Suggested retest entry',
              value: _formatQuote(suggestedSetup.entry!, signal.pair),
              color: _white,
            ),
            const SizedBox(height: 6),
            Text(
              'Zone midpoint · ${suggestedSetup.confluenceScore ?? 0}/100 evidence score, not a probability. This is a chart reference, not an order.',
              style: TextStyle(color: _muted, fontSize: 9, height: 1.4),
            ),
          ],
          Divider(height: 22, color: _line),
          _InfoLine(
            label: 'Current bid / ask',
            value:
                '${_formatQuote(signal.bid, signal.pair)} / ${_formatQuote(signal.ask, signal.pair)}',
            color: _white,
          ),
          const SizedBox(height: 10),
          _InfoLine(
            label: 'Entry',
            value: signal.hasSignal ? signal.entry : '—',
            color: _white,
          ),
          const SizedBox(height: 10),
          _InfoLine(
            label: 'Stop loss',
            value: signal.hasSignal ? signal.stop : '—',
            color: signal.hasSignal ? _red : _muted,
          ),
          const SizedBox(height: 10),
          _InfoLine(
            label: 'Take profit',
            value: signal.hasSignal ? signal.target : '—',
            color: signal.hasSignal ? _green : _muted,
          ),
          const SizedBox(height: 10),
          _InfoLine(
            label: 'Status',
            value: signal.status,
            color: directionColor,
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              '${signal.setup} This is analysis, not a guarantee or investment advice.',
              style: TextStyle(color: _blue, fontSize: 9, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _AnalysisCheck extends StatelessWidget {
  const _AnalysisCheck(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label, style: TextStyle(color: _muted, fontSize: 9)),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeframeRoadmap extends StatelessWidget {
  const _TimeframeRoadmap();

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelHeading(
            title: 'Market-mechanism analysis',
            subtitle:
                'Score the context and entry evidence; not every check must be complete',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              _TimeframeCard('4H', 'Market-structure bias', _blue),
              _TimeframeCard('1H', 'Structure and liquidity levels', _lime),
              _TimeframeCard(
                '15M',
                'Sweep → displacement → BOS/CHoCH → entry zone',
                _amber,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeframeCard extends StatelessWidget {
  const _TimeframeCard(this.timeframe, this.label, this.color);

  final String timeframe;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 140),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _background,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            timeframe,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(color: _muted, fontSize: 9)),
        ],
      ),
    );
  }
}

class _PositionsPage extends StatelessWidget {
  const _PositionsPage({
    required this.account,
    required this.message,
    required this.loading,
    required this.markets,
    required this.accountMode,
    required this.eurusdTimeframe,
    required this.onEurusdTimeframeChanged,
    required this.usdcadTimeframe,
    required this.onUsdcadTimeframeChanged,
    required this.xauusdTimeframe,
    required this.onXauusdTimeframeChanged,
    required this.onOpenSettings,
    required this.onRefresh,
  });

  final DemoAccountSnapshot? account;
  final String message;
  final bool loading;
  final List<MarketSignal> markets;
  final String accountMode;
  final String eurusdTimeframe;
  final ValueChanged<String> onEurusdTimeframeChanged;
  final String usdcadTimeframe;
  final ValueChanged<String> onUsdcadTimeframeChanged;
  final String xauusdTimeframe;
  final ValueChanged<String> onXauusdTimeframeChanged;
  final VoidCallback onOpenSettings;
  final Future<void> Function() onRefresh;

  Widget _positionChart({
    required String symbol,
    required MarketSignal? signal,
    required String timeframe,
    required ValueChanged<String> onTimeframeChanged,
    required String timeframeKeyPrefix,
  }) {
    if (signal == null) {
      return _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PanelHeading(
              title: '$symbol position chart',
              subtitle: 'Waiting for market chart data from closed candles',
            ),
            const SizedBox(height: 8),
            Text(
              'Connect the market feed to view the $symbol chart.',
              style: TextStyle(color: _muted, fontSize: 10),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$symbol position chart',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        _ChartPanel(
          signal: signal,
          timeframe: timeframe,
          onTimeframeChanged: onTimeframeChanged,
          height: 320,
          timeframeKeyPrefix: timeframeKeyPrefix,
          showPositionTimeframes: true,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final account = this.account;
    MarketSignal? marketFor(String symbol) {
      for (final market in markets) {
        if (market.pair == symbol) {
          return market;
        }
      }
      return null;
    }

    final eurusd = marketFor('EURUSD');
    final usdcad = marketFor('USDCAD');
    final xauusd = marketFor('XAUUSD');
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TradingNotice(mode: accountMode),
          const SizedBox(height: 21),
          const Text(
            'Account & positions',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            'Connected ${accountMode.toUpperCase()} MT5 account · credentials are not saved by the app',
            style: TextStyle(color: _muted, fontSize: 10),
          ),
          const SizedBox(height: 15),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _PanelHeading(
                        title: 'Account summary',
                        subtitle: 'Read from the connected local MT5 terminal',
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh account',
                      onPressed: loading ? null : onRefresh,
                      icon: loading
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (account == null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        message,
                        style: TextStyle(
                          color: _muted,
                          fontSize: 10,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: onOpenSettings,
                        icon: const Icon(Icons.login_rounded, size: 16),
                        label: const Text('Connect MT5 account in Settings'),
                      ),
                    ],
                  )
                else ...[
                  Text(
                    '${account.accountMode.toUpperCase()} · ${account.login} · ${account.server}',
                    style: TextStyle(
                      color: _green,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 28,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 230,
                        child: _InfoLine(
                          label: 'BALANCE',
                          value:
                              '${account.balance.toStringAsFixed(2)} ${account.currency}',
                          color: _white,
                        ),
                      ),
                      SizedBox(
                        width: 230,
                        child: _InfoLine(
                          label: 'EQUITY',
                          value:
                              '${account.equity.toStringAsFixed(2)} ${account.currency}',
                          color: _white,
                        ),
                      ),
                      SizedBox(
                        width: 230,
                        child: _InfoLine(
                          label: 'FLOATING P/L',
                          value:
                              '${account.profit.toStringAsFixed(2)} ${account.currency}',
                          color: account.profit >= 0 ? _green : _red,
                        ),
                      ),
                      SizedBox(
                        width: 230,
                        child: _InfoLine(
                          label: 'FREE MARGIN',
                          value:
                              '${account.freeMargin.toStringAsFixed(2)} ${account.currency}',
                          color: _white,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          _positionChart(
            symbol: 'EURUSD',
            signal: eurusd,
            timeframe: eurusdTimeframe,
            onTimeframeChanged: onEurusdTimeframeChanged,
            timeframeKeyPrefix: 'eurusd-position-chart',
          ),
          const SizedBox(height: 14),
          _positionChart(
            symbol: 'USDCAD',
            signal: usdcad,
            timeframe: usdcadTimeframe,
            onTimeframeChanged: onUsdcadTimeframeChanged,
            timeframeKeyPrefix: 'usdcad-position-chart',
          ),
          const SizedBox(height: 14),
          _positionChart(
            symbol: 'XAUUSD',
            signal: xauusd,
            timeframe: xauusdTimeframe,
            onTimeframeChanged: onXauusdTimeframeChanged,
            timeframeKeyPrefix: 'xauusd-position-chart',
          ),
          const SizedBox(height: 14),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _PanelHeading(
                  title: 'Open positions',
                  subtitle: 'Position data is refreshed every 15 seconds',
                ),
                const SizedBox(height: 10),
                if (account == null)
                  Text(
                    'Connect the Windows app to the selected MT5 account to view positions.',
                    style: TextStyle(color: _muted, fontSize: 10, height: 1.5),
                  )
                else if (account.positions.isEmpty)
                  Text(
                    'No open positions on this account.',
                    style: TextStyle(color: _muted, fontSize: 10),
                  )
                else
                  for (final position in account.positions)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: _InfoLine(
                        label:
                            '${position.direction} ${position.symbol} · ${position.volume} lots',
                        value:
                            '${position.profit.toStringAsFixed(2)} ${account.currency}',
                        color: position.profit >= 0 ? _green : _red,
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryPage extends StatefulWidget {
  const _HistoryPage({
    required this.mode,
    required this.feedUrl,
    required this.tradingService,
  });

  final String mode;
  final String feedUrl;
  final DemoTradingService tradingService;

  @override
  State<_HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<_HistoryPage> {
  TradeHistorySnapshot? _history;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final history = await widget.tradingService.fetchHistory(widget.feedUrl);
      if (!mounted) return;
      setState(() => _history = history);
    } on MarketFeedException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _timeLabel(DateTime value) {
    final local = value.toLocal();
    final date =
        '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    return '$date · $time';
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _history;
    final deals =
        snapshot?.deals
            .where((deal) => deal.automated)
            .toList(growable: false) ??
        const <TradeHistoryEntry>[];
    final net = deals.fold<double>(0, (sum, deal) => sum + deal.netProfit);
    final currency = snapshot?.currency ?? 'USD';

    return _PageScroll(
      topPadding: 8,
      fillViewport: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trade history',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      'ARTIFACTS bot executions from the last 30 days',
                      style: TextStyle(color: _muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh history',
                onPressed: _loading ? null : _refresh,
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 15),
          if (_error != null)
            _Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'History unavailable',
                    style: TextStyle(
                      color: _amber,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(color: _muted, fontSize: 10, height: 1.45),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _refresh,
                    icon: const Icon(Icons.refresh_rounded, size: 15),
                    label: const Text('Try again'),
                  ),
                ],
              ),
            )
          else if (_loading && snapshot == null)
            _Panel(
              child: Row(
                children: [
                  const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Loading ${widget.mode.toUpperCase()} broker history…',
                    style: TextStyle(color: _muted, fontSize: 10),
                  ),
                ],
              ),
            )
          else ...[
            _Panel(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final summary = Row(
                    children: [
                      Expanded(
                        child: _InfoLine(
                          label: 'BOT NET P/L',
                          value:
                              '${net >= 0 ? '+' : ''}${net.toStringAsFixed(2)} $currency',
                          color: net >= 0 ? _green : _red,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _InfoLine(
                          label: 'EXECUTIONS',
                          value: '${deals.length}',
                          color: _white,
                        ),
                      ),
                    ],
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _PanelHeading(
                        title: 'ARTIFACTS bot activity',
                        subtitle: 'Up to 200 most recent bot deal records',
                      ),
                      const SizedBox(height: 14),
                      if (constraints.maxWidth < 430)
                        Column(
                          children: [
                            _InfoLine(
                              label: 'BOT NET P/L',
                              value:
                                  '${net >= 0 ? '+' : ''}${net.toStringAsFixed(2)} $currency',
                              color: net >= 0 ? _green : _red,
                            ),
                            const SizedBox(height: 12),
                            _InfoLine(
                              label: 'EXECUTIONS',
                              value: '${deals.length}',
                              color: _white,
                            ),
                          ],
                        )
                      else
                        summary,
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 12),
            _Panel(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: deals.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 22),
                      child: Center(
                        child: Text(
                          snapshot == null
                              ? 'Connect to the authorized Windows MT5 session to load bot history.'
                              : 'No ARTIFACTS bot executions in the last 30 days.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _muted,
                            fontSize: 10,
                            height: 1.5,
                          ),
                        ),
                      ),
                    )
                  : Column(
                      children: [
                        for (final deal in deals)
                          _HistoryDealRow(
                            deal: deal,
                            timeLabel: _timeLabel(deal.time),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 10),
            Text(
              'Net P/L is the sum of the displayed deal records (profit, commission, swap, and fees). Broker fills may appear as separate executions.',
              style: TextStyle(color: _muted, fontSize: 9, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }
}

class _HistoryDealRow extends StatelessWidget {
  const _HistoryDealRow({required this.deal, required this.timeLabel});

  final TradeHistoryEntry deal;
  final String timeLabel;

  @override
  Widget build(BuildContext context) {
    final profitColor = deal.netProfit >= 0 ? _green : _red;
    final directionColor = deal.direction == 'BUY'
        ? _green
        : deal.direction == 'SELL'
        ? _red
        : _muted;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              color: directionColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              deal.direction == 'BUY'
                  ? Icons.north_east_rounded
                  : deal.direction == 'SELL'
                  ? Icons.south_east_rounded
                  : Icons.receipt_long_rounded,
              color: directionColor,
              size: 16,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 7,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      deal.symbol,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    _Tag(label: deal.direction, color: directionColor),
                    _Tag(label: deal.entry, color: _muted),
                    _Tag(label: 'BOT', color: _amber),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$timeLabel · ${deal.volume.toStringAsFixed(2)} lots · ${deal.price}',
                  style: TextStyle(color: _muted, fontSize: 9),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${deal.netProfit >= 0 ? '+' : ''}${deal.netProfit.toStringAsFixed(2)}',
            textAlign: TextAlign.end,
            style: TextStyle(
              color: profitColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _AutomationPage extends StatelessWidget {
  const _AutomationPage({
    required this.enabled,
    required this.botEnabled,
    required this.riskPerTrade,
    required this.accountMode,
    required this.onRiskChanged,
    required this.onToggleBot,
    required this.onToggle,
  });

  final bool enabled;
  final bool botEnabled;
  final double riskPerTrade;
  final String accountMode;
  final ValueChanged<double> onRiskChanged;
  final VoidCallback onToggleBot;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TradingNotice(mode: accountMode),
          const SizedBox(height: 21),
          const Text(
            'Automation controls',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            '${accountMode.toUpperCase()} account · bot trading ${botEnabled ? 'enabled' : 'disabled'}',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
          const SizedBox(height: 17),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PanelHeading(
                  title: botEnabled
                      ? 'Automated bot enabled'
                      : 'Automated bot disabled',
                  subtitle:
                      'Runs every 15 seconds while the authorized Windows service is running. With a liquidity sweep, 7/13–8/13 opens two 0.10-lot scalps targeting \$4 each on hedging accounts; 9/13+ keeps the existing single-entry behavior. XAUUSD is excluded; no session-time filter.',
                ),
                const SizedBox(height: 12),
                Text(
                  '7/13–8/13: two 0.10-lot positions with \$4 take-profit each; 0.5% maximum estimated risk per order (up to 1% combined). 9/13+: existing 0.10-lot entry, signal TP, and at most one 0.01-lot add-on after +1R with pullback no greater than 0.5× 15M ATR. Stops ratchet by \$1 profit steps up to \$5. A 1.5× ATR directional 15M impulse holds the trade until 23:59 UTC; broker SL/TP remain active.',
                  style: TextStyle(color: _muted, fontSize: 10, height: 1.5),
                ),
                const SizedBox(height: 13),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onToggleBot,
                    child: Text(
                      botEnabled
                          ? 'Disable automated bot'
                          : 'Enable automated bot',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 13),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PanelHeading(
                  title: enabled
                      ? 'Manual order review enabled'
                      : 'Manual order review disabled',
                  subtitle:
                      'This separate setting controls manually reviewed orders. Every manual order still requires your review and confirmation.',
                ),
                const SizedBox(height: 13),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: onToggle,
                    child: Text(
                      enabled
                          ? 'Disable manual order review'
                          : 'Enable manual order review',
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 13),
          _RiskSettingsCard(
            riskPerTrade: riskPerTrade,
            onRiskChanged: onRiskChanged,
          ),
        ],
      ),
    );
  }
}

class _RiskSettingsCard extends StatelessWidget {
  const _RiskSettingsCard({
    required this.riskPerTrade,
    required this.onRiskChanged,
  });

  final double riskPerTrade;
  final ValueChanged<double> onRiskChanged;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelHeading(
            title: 'Manual order risk limit',
            subtitle: 'Applied only to manually reviewed orders',
          ),
          const SizedBox(height: 17),
          _SliderSetting(
            title: 'Risk per trade',
            valueText: '${riskPerTrade.toStringAsFixed(2)}%',
            value: riskPerTrade,
            min: 0.1,
            max: 0.5,
            divisions: 8,
            onChanged: onRiskChanged,
          ),
          Text(
            'Orders are limited to 0.5% estimated stop risk. Slippage and price gaps can exceed estimated risk.',
            style: TextStyle(color: _muted, fontSize: 9, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _SliderSetting extends StatelessWidget {
  const _SliderSetting({
    required this.title,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String title;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: const TextStyle(fontSize: 10))),
            Text(
              valueText,
              style: TextStyle(
                color: _lime,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          activeColor: _lime,
          inactiveColor: _line,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _FeedSettingsCard extends StatefulWidget {
  const _FeedSettingsCard({
    required this.feedUrl,
    required this.connected,
    required this.message,
    required this.source,
    required this.onSave,
    required this.onRefresh,
  });

  final String feedUrl;
  final bool connected;
  final String message;
  final String source;
  final ValueChanged<String> onSave;
  final VoidCallback onRefresh;

  @override
  State<_FeedSettingsCard> createState() => _FeedSettingsCardState();
}

class _FeedSettingsCardState extends State<_FeedSettingsCard> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.feedUrl);
  }

  @override
  void didUpdateWidget(covariant _FeedSettingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.feedUrl != widget.feedUrl &&
        _controller.text != widget.feedUrl) {
      _controller.text = widget.feedUrl;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.connected ? _green : _amber;
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeading(
            title: 'Live market data',
            subtitle: widget.source,
            actionLabel: widget.connected ? 'CONNECTED' : 'OFFLINE',
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Icon(
                widget.connected
                    ? Icons.cloud_done_rounded
                    : Icons.cloud_off_rounded,
                size: 16,
                color: tint,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.message,
                  style: TextStyle(color: tint, fontSize: 9),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          const _FieldLabel('LOCAL MT5 FEED ADDRESS'),
          const SizedBox(height: 6),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              hintText: 'http://127.0.0.1:8765',
              prefixIcon: Icon(Icons.link_rounded, size: 17),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 9,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => widget.onSave(_controller.text),
                icon: const Icon(Icons.save_outlined, size: 15),
                label: const Text('Save feed address'),
                style: FilledButton.styleFrom(
                  backgroundColor: _lime,
                  foregroundColor: _background,
                ),
              ),
              OutlinedButton.icon(
                onPressed: widget.onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 15),
                label: const Text('Refresh now'),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            'On Android over USB, forward the local feed with: adb reverse tcp:8765 tcp:8765',
            style: TextStyle(color: _muted, fontSize: 9, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.accountNumber,
    required this.server,
    required this.accountStatus,
    required this.accountConnected,
    required this.accountConnecting,
    required this.canRetryFeed,
    required this.onRetryFeed,
    required this.environment,
    required this.notificationsEnabled,
    required this.lightTheme,
    required this.feedUrl,
    required this.feedConnected,
    required this.feedMessage,
    required this.feedSource,
    required this.onNotificationsChanged,
    required this.onLightThemeChanged,
    required this.onEnvironmentChanged,
    required this.onFeedUrlSaved,
    required this.onRefresh,
    required this.onConnect,
  });

  final String accountNumber;
  final String server;
  final String accountStatus;
  final bool accountConnected;
  final bool accountConnecting;
  final bool canRetryFeed;
  final VoidCallback onRetryFeed;
  final String environment;
  final bool notificationsEnabled;
  final bool lightTheme;
  final String feedUrl;
  final bool feedConnected;
  final String feedMessage;
  final String feedSource;
  final ValueChanged<bool> onNotificationsChanged;
  final ValueChanged<bool> onLightThemeChanged;
  final ValueChanged<String> onEnvironmentChanged;
  final ValueChanged<String> onFeedUrlSaved;
  final VoidCallback onRefresh;
  final Future<void> Function({
    required String login,
    required String password,
    required String server,
  })
  onConnect;

  @override
  Widget build(BuildContext context) {
    return _PageScroll(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TradingNotice(mode: environment),
          const SizedBox(height: 21),
          const Text(
            'Settings & accounts',
            style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            'Choose account mode and manage local preferences',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
          const SizedBox(height: 17),
          _FeedSettingsCard(
            feedUrl: feedUrl,
            connected: feedConnected,
            message: feedMessage,
            source: feedSource,
            onSave: onFeedUrlSaved,
            onRefresh: onRefresh,
          ),
          const SizedBox(height: 13),
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 860;
              final account = _AccountSettingsCard(
                accountNumber: accountNumber,
                server: server,
                status: accountStatus,
                connected: accountConnected,
                connecting: accountConnecting,
                canRetryFeed: canRetryFeed,
                onRetryFeed: onRetryFeed,
                environment: environment,
                onEnvironmentChanged: onEnvironmentChanged,
                onConnect: onConnect,
              );
              final preferences = _PreferencesCard(
                notificationsEnabled: notificationsEnabled,
                onNotificationsChanged: onNotificationsChanged,
                lightTheme: lightTheme,
                onLightThemeChanged: onLightThemeChanged,
              );
              if (stacked) {
                return Column(
                  children: [account, const SizedBox(height: 13), preferences],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: account),
                  const SizedBox(width: 13),
                  Expanded(flex: 5, child: preferences),
                ],
              );
            },
          ),
          const SizedBox(height: 13),
          _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _PanelHeading(
                  title: 'Live feed status',
                  subtitle:
                      'The selected broker account is connected through the local MT5 terminal',
                ),
                const SizedBox(height: 12),
                const SizedBox(height: 7),
                Text(
                  'Connect using your MT5 login, broker server, and trading password. Credentials are sent to the local Windows MT5 service for sign-in, are not saved by the app, and the password field is cleared after each attempt. Bot trading is disabled until explicitly enabled in Automation; each manual order requires review and confirmation.',
                  style: TextStyle(color: _muted, fontSize: 9, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountSettingsCard extends StatefulWidget {
  const _AccountSettingsCard({
    required this.accountNumber,
    required this.server,
    required this.status,
    required this.connected,
    required this.connecting,
    required this.canRetryFeed,
    required this.onRetryFeed,
    required this.environment,
    required this.onEnvironmentChanged,
    required this.onConnect,
  });

  final String accountNumber;
  final String server;
  final String status;
  final bool connected;
  final bool connecting;
  final bool canRetryFeed;
  final VoidCallback onRetryFeed;
  final String environment;
  final ValueChanged<String> onEnvironmentChanged;
  final Future<void> Function({
    required String login,
    required String password,
    required String server,
  })
  onConnect;

  @override
  State<_AccountSettingsCard> createState() => _AccountSettingsCardState();
}

class _AccountSettingsCardState extends State<_AccountSettingsCard> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _loginController;
  late final TextEditingController _serverController;
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _connecting = false;

  @override
  void initState() {
    super.initState();
    _loginController = TextEditingController(
      text: widget.accountNumber == '—' ? '' : widget.accountNumber,
    );
    _serverController = TextEditingController(
      text: widget.server == 'MetaTrader 5' ? '' : widget.server,
    );
  }

  @override
  void didUpdateWidget(covariant _AccountSettingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountNumber != widget.accountNumber &&
        (_loginController.text.isEmpty ||
            _loginController.text == oldWidget.accountNumber)) {
      _loginController.text = widget.accountNumber == '—'
          ? ''
          : widget.accountNumber;
    }
    if (oldWidget.server != widget.server &&
        (_serverController.text.isEmpty ||
            _serverController.text == oldWidget.server)) {
      _serverController.text = widget.server == 'MetaTrader 5'
          ? ''
          : widget.server;
    }
  }

  @override
  void dispose() {
    _loginController.dispose();
    _serverController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submitConnection() async {
    if (_connecting || !(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _connecting = true);
    final password = _passwordController.text;
    try {
      await widget.onConnect(
        login: _loginController.text.trim(),
        password: password,
        server: _serverController.text.trim(),
      );
    } finally {
      _passwordController.clear();
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelHeading(
            title: 'MetaTrader 5 account',
            subtitle:
                'Connect your broker credentials to the local MT5 terminal',
            actionLabel: widget.environment.toUpperCase(),
          ),
          const SizedBox(height: 13),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: _amber.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: _amber.withValues(alpha: 0.17)),
            ),
            child: Text(
              'Credentials are sent only to this computer’s local MT5 service to sign in. The app does not save your password. Use your broker’s MT5 trading password, not an investor/read-only password.',
              style: TextStyle(color: _amber, fontSize: 9, height: 1.45),
            ),
          ),
          const SizedBox(height: 11),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color:
                  (widget.connected
                          ? _green
                          : widget.connecting
                          ? _amber
                          : _red)
                      .withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color:
                    (widget.connected
                            ? _green
                            : widget.connecting
                            ? _amber
                            : _red)
                        .withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  widget.connected
                      ? Icons.check_circle_outline_rounded
                      : widget.connecting
                      ? Icons.hourglass_top_rounded
                      : Icons.error_outline_rounded,
                  size: 15,
                  color: widget.connected
                      ? _green
                      : widget.connecting
                      ? _amber
                      : _red,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.status,
                    key: const ValueKey('mt5-account-connection-status'),
                    style: TextStyle(
                      color: widget.connected
                          ? _green
                          : widget.connecting
                          ? _amber
                          : _red,
                      fontSize: 9,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.canRetryFeed) ...[
            const SizedBox(height: 9),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: widget.connecting ? null : widget.onRetryFeed,
                icon: widget.connecting
                    ? const SizedBox.square(
                        dimension: 13,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 15),
                label: Text(
                  widget.connecting
                      ? 'Starting local service…'
                      : 'Start / retry local MT5 service',
                ),
              ),
            ),
          ],
          const SizedBox(height: 15),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _FieldLabel('MT5 ACCOUNT LOGIN'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _loginController,
                  keyboardType: TextInputType.number,
                  enabled: !_connecting,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter your MT5 account login.'
                      : null,
                  decoration: InputDecoration(
                    hintText: 'Account number from your broker',
                    prefixIcon: const Icon(
                      Icons.person_outline_rounded,
                      size: 17,
                    ),
                  ),
                ),
                const SizedBox(height: 13),
                const _FieldLabel('BROKER SERVER'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _serverController,
                  enabled: !_connecting,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter the exact MT5 server name.'
                      : null,
                  decoration: const InputDecoration(
                    hintText: 'Exact server name, e.g. Broker-Live',
                    prefixIcon: Icon(Icons.dns_outlined, size: 17),
                  ),
                ),
                const SizedBox(height: 13),
                const _FieldLabel('MT5 TRADING PASSWORD'),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _passwordController,
                  enabled: !_connecting,
                  obscureText: _obscurePassword,
                  validator: (value) => value == null || value.isEmpty
                      ? 'Enter your MT5 trading password.'
                      : null,
                  decoration: InputDecoration(
                    hintText: 'Used once to connect; never saved',
                    prefixIcon: const Icon(
                      Icons.lock_outline_rounded,
                      size: 17,
                    ),
                    suffixIcon: IconButton(
                      tooltip: _obscurePassword
                          ? 'Show password'
                          : 'Hide password',
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 17,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 13),
          const _FieldLabel('ACCOUNT ENVIRONMENT'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final option in ['demo', 'live'])
                ChoiceChip(
                  label: Text(option.toUpperCase()),
                  selected: widget.environment == option,
                  onSelected: (selected) {
                    if (!selected) return;
                    widget.onEnvironmentChanged(option);
                  },
                  selectedColor: _lime.withValues(alpha: 0.12),
                  side: BorderSide(
                    color: widget.environment == option ? _lime : _line,
                  ),
                  labelStyle: TextStyle(
                    color: widget.environment == option ? _lime : _muted,
                    fontSize: 10,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _connecting ? null : _submitConnection,
              icon: _connecting
                  ? const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link_rounded, size: 16),
              style: FilledButton.styleFrom(
                backgroundColor: _lime,
                foregroundColor: _background,
              ),
              label: Text(_connecting ? 'Connecting…' : 'Connect MT5 account'),
            ),
          ),
          const SizedBox(height: 11),
          Row(
            children: [
              Icon(Icons.lock_outline_rounded, size: 13, color: _muted),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Password is cleared after connection. Live orders still require your review and confirmation.',
                  style: TextStyle(color: _muted, fontSize: 8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: _muted,
        fontSize: 8,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
  }
}

class _PreferencesCard extends StatelessWidget {
  const _PreferencesCard({
    required this.notificationsEnabled,
    required this.onNotificationsChanged,
    required this.lightTheme,
    required this.onLightThemeChanged,
  });

  final bool notificationsEnabled;
  final ValueChanged<bool> onNotificationsChanged;
  final bool lightTheme;
  final ValueChanged<bool> onLightThemeChanged;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _PanelHeading(
            title: 'Preferences',
            subtitle: 'Local app settings',
          ),
          const SizedBox(height: 11),
          Material(
            color: _panel,
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: notificationsEnabled,
              activeTrackColor: _lime,
              onChanged: onNotificationsChanged,
              title: const Text(
                'Signal notifications',
                style: TextStyle(fontSize: 10),
              ),
              subtitle: Text(
                'In-app alerts in this preview',
                style: TextStyle(color: _muted, fontSize: 9),
              ),
            ),
          ),
          Divider(color: _line),
          const _PreferenceRow(
            icon: Icons.language_rounded,
            title: 'Language',
            value: 'English',
          ),
          Material(
            color: _panel,
            child: SwitchListTile.adaptive(
              key: const ValueKey('light-theme-toggle'),
              contentPadding: EdgeInsets.zero,
              value: lightTheme,
              activeTrackColor: _lime,
              onChanged: onLightThemeChanged,
              title: const Text('Light theme', style: TextStyle(fontSize: 10)),
              subtitle: Text(
                'Use a light appearance throughout the app',
                style: TextStyle(color: _muted, fontSize: 9),
              ),
            ),
          ),
          const _PreferenceRow(
            icon: Icons.devices_outlined,
            title: 'Platforms',
            value: 'Android · Web · Windows',
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: _background,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              'Account secrets, passwords, and broker tokens are not stored by this app.',
              style: TextStyle(color: _muted, fontSize: 9, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreferenceRow extends StatelessWidget {
  const _PreferenceRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        children: [
          Icon(icon, color: _muted, size: 15),
          const SizedBox(width: 9),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 9))),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(color: _muted, fontSize: 8),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: _muted,
        fontSize: 8,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}
