import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'transport.dart';

/// Replays a real, read-only ELM327 capture for UI and parser testing.
/// It is deliberately not wired into the physical adapter flow.
class MockReplayTransport implements Transport {
  final String assetPath;
  final bool preserveLatency;
  final List<String> sentCommands = [];
  final List<Map<String, dynamic>> _entries = [];
  bool _connected = false;
  int _cursor = 0;

  MockReplayTransport({
    this.assetPath = 'assets/fixtures/fluence_real_capture.json',
    this.preserveLatency = false,
  });

  @override
  bool get isConnected => _connected;

  @override
  Future<bool> connect() async {
    final json = jsonDecode(await rootBundle.loadString(assetPath));
    final raw = json is Map ? json['rawCapture'] : json;
    if (raw is! List) throw StateError('Replay fixture has no rawCapture list');
    _entries
      ..clear()
      ..addAll(raw.whereType<Map>().map((entry) => Map<String, dynamic>.from(entry)));
    if (_entries.isEmpty) throw StateError('Replay fixture contains no capture entries');
    _cursor = 0;
    _connected = true;
    return true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _entries.clear();
    _cursor = 0;
  }

  @override
  Future<String> sendAndAwait(String command, {Duration timeout = const Duration(seconds: 4)}) async {
    final normalized = command.trim().toUpperCase();
    sentCommands.add(normalized);
    if (!_connected) return 'DISCONNECTED';

    Map<String, dynamic>? match;
    for (var offset = 0; offset < _entries.length; offset++) {
      final index = (_cursor + offset) % _entries.length;
      final candidate = _entries[index];
      if (candidate['request']?.toString().trim().toUpperCase() == normalized) {
        match = candidate;
        _cursor = (index + 1) % _entries.length;
        break;
      }
    }
    match ??= _entries.firstWhere(
      (entry) => entry['request']?.toString().trim().toUpperCase() == normalized,
      orElse: () => <String, dynamic>{'response': 'NO DATA'},
    );
    if (preserveLatency) {
      final milliseconds = (match['latencyMs'] as num?)?.toInt() ?? 50;
      await Future<void>.delayed(Duration(milliseconds: milliseconds));
    }
    return match['response']?.toString() ?? 'NO DATA';
  }
}
