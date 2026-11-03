class FeedServerLauncher {
  bool get supported => false;

  String? get accessToken => null;

  String? get baseUrl => null;

  Future<void> startIfNeeded({String accountMode = 'demo'}) async {}

  Future<void> stop() async {}
}

class FeedServerStartException implements Exception {
  const FeedServerStartException(this.message);

  final String message;

  @override
  String toString() => message;
}
