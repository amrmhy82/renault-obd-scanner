import 'dart:convert';

/// A transport-level transaction captured before any OBD/UDS interpretation.
/// The raw request and response remain available even when parsing fails.
class RawCaptureEntry {
  final DateTime timestamp;
  final String transport;
  final String command;
  final String rawResponse;
  final int latencyMs;
  final bool isError;

  const RawCaptureEntry({
    required this.timestamp,
    required this.transport,
    required this.command,
    required this.rawResponse,
    required this.latencyMs,
    required this.isError,
  });

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'transport': transport,
        'direction': 'TX/RX',
        'request': command,
        'response': rawResponse,
        'latencyMs': latencyMs,
        'error': isError,
      };
}

/// Bounded in-memory capture for the current diagnostic session.
/// Persistence/export is deliberately separate from protocol parsing.
class RawCaptureStore {
  final int maxEntries;
  final List<RawCaptureEntry> _entries = [];

  RawCaptureStore({this.maxEntries = 2000});

  List<RawCaptureEntry> get entries => List.unmodifiable(_entries);

  void record(RawCaptureEntry entry) {
    _entries.add(entry);
    if (_entries.length > maxEntries) _entries.removeAt(0);
  }

  void clear() => _entries.clear();

  String toJson() => const JsonEncoder.withIndent('  ').convert(
        _entries.map((entry) => entry.toJson()).toList(),
      );
}
