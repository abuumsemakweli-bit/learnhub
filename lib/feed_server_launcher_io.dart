import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';

class FeedServerLauncher {
  Process? _process;
  Directory? _workingDirectory;
  String? _accessToken;
  final StringBuffer _stderr = StringBuffer();

  bool get supported => Platform.isWindows;

  String? get accessToken => _accessToken;

  String? get baseUrl => _port == null ? null : 'http://127.0.0.1:$_port';

  int? _port;

  Future<void> startIfNeeded({String accountMode = 'demo'}) async {
    if (!supported) return;
    if (_process != null &&
        _accessToken != null &&
        _port != null &&
        await _isFeedResponding(_port!)) {
      return;
    }

    final random = Random.secure();
    _accessToken = List<int>.generate(
      32,
      (_) => random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    final workingDirectory = await Directory.systemTemp.createTemp(
      'smc_trader_feed_',
    );
    _workingDirectory = workingDirectory;
    try {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _port = socket.port;
      await socket.close();
      await _writeAsset(
        'mt5_feed/server.py',
        '${workingDirectory.path}\\server.py',
      );
      await _writeAsset(
        'mt5_feed/signal_engine.py',
        '${workingDirectory.path}\\signal_engine.py',
      );
      _process = await _startPython(workingDirectory.path, accountMode, _port!);
      _process!.stderr
          .transform(const SystemEncoding().decoder)
          .listen(_recordStderr);
      unawaited(_process!.stdout.drain<void>());

      final started = await _waitUntilResponding(_process!, _port!);
      if (!started) {
        final details = _stderr.toString().trim();
        throw FeedServerStartException(
          details.isEmpty
              ? 'The local MT5 feed did not start. Check that Python, the MT5 package, and MetaTrader 5 are installed.'
              : 'The local MT5 feed did not start: $details',
        );
      }
    } on FeedServerStartException {
      await stop();
      rethrow;
    } on Object catch (error) {
      await stop();
      throw FeedServerStartException(
        'Could not start the local MT5 feed. Install Python and the packages in mt5_feed\\requirements.txt. Details: $error',
      );
    }
  }

  Future<void> _writeAsset(String asset, String destination) async {
    final data = await rootBundle.load(asset);
    await File(destination).writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
  }

  Future<Process> _startPython(
    String workingDirectory,
    String accountMode,
    int port,
  ) async {
    try {
      return await Process.start(
        'python',
        ['server.py', '--host', '127.0.0.1', '--port', '$port'],
        workingDirectory: workingDirectory,
        environment: {
          ...Platform.environment,
          'AURUM_TRADING_TOKEN': _accessToken!,
          'AURUM_ACCOUNT_MODE': accountMode,
        },
      );
    } on ProcessException {
      return Process.start(
        'py',
        ['-3', 'server.py', '--host', '127.0.0.1', '--port', '$port'],
        workingDirectory: workingDirectory,
        environment: {
          ...Platform.environment,
          'AURUM_TRADING_TOKEN': _accessToken!,
          'AURUM_ACCOUNT_MODE': accountMode,
        },
      );
    }
  }

  Future<bool> _waitUntilResponding(Process process, int port) async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    var exited = false;
    unawaited(process.exitCode.then((_) => exited = true));
    while (DateTime.now().isBefore(deadline)) {
      if (await _isFeedResponding(port)) return true;
      if (exited) return false;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return _isFeedResponding(port);
  }

  Future<bool> _isFeedResponding(int port) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 1);
    try {
      final request = await client
          .getUrl(Uri.parse('http://127.0.0.1:$port/health'))
          .timeout(const Duration(seconds: 1));
      final response = await request.close().timeout(
        const Duration(seconds: 1),
      );
      await response.drain<void>();
      final server = response.headers.value(HttpHeaders.serverHeader) ?? '';
      return server.startsWith('AurumTradingFeed/');
    } on IOException {
      return false;
    } on TimeoutException {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  void _recordStderr(String message) {
    _stderr.write(message);
    if (_stderr.length > 4000) {
      final recentOutput = _stderr.toString();
      _stderr
        ..clear()
        ..write(recentOutput.substring(recentOutput.length - 4000));
    }
  }

  Future<void> stop() async {
    _accessToken = null;
    _port = null;
    final process = _process;
    _process = null;
    if (process != null) {
      process.kill();
      await process.exitCode;
    }
    final directory = _workingDirectory;
    _workingDirectory = null;
    if (directory != null && await directory.exists()) {
      await directory.delete(recursive: true);
    }
  }
}

class FeedServerStartException implements Exception {
  const FeedServerStartException(this.message);

  final String message;

  @override
  String toString() => message;
}
