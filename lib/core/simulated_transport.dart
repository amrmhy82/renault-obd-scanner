import 'transport.dart';

/// Deterministic ELM327 transport for local tests and replay tools.
/// It is never used by the vehicle connection flow.
class SimulatedElm327Transport implements Transport {
  final Map<String, String> responses;
  final Duration responseDelay;
  final Set<String> timeoutCommands;
  bool _connected;
  final List<String> sentCommands = [];

  SimulatedElm327Transport({
    required this.responses,
    this.responseDelay = Duration.zero,
    this.timeoutCommands = const {},
    bool connected = true,
  }) : _connected = connected;

  @override
  bool get isConnected => _connected;

  @override
  Future<bool> connect() async {
    _connected = true;
    return true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  void setConnected(bool value) => _connected = value;

  @override
  Future<String> sendAndAwait(String command, {Duration timeout = const Duration(seconds: 4)}) async {
    sentCommands.add(command);
    if (responseDelay > Duration.zero) await Future<void>.delayed(responseDelay);
    if (!_connected) return 'DISCONNECTED';
    if (timeoutCommands.contains(command)) return 'TIMEOUT';
    return responses[command] ?? 'NO DATA';
  }
}
