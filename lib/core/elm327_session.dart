import 'dart:async';
import 'command_queue.dart';
import 'elm_session_state.dart';
import 'init_command.dart';
import 'obd_response_utils.dart';
import 'pid_registry.dart';
import 'transport.dart';

class DebugLogEntry {
  final DateTime time;
  final String command;
  final String rawResponse;
  final int latencyMs;
  final bool isError;
  DebugLogEntry(this.time, this.command, this.rawResponse, this.latencyMs, this.isError);
}

/// استُثنيت التهيئة عند فشل أحد أوامر AT (بدل الاستمرار بصمت وكأن كل شيء تمام)
class Elm327InitializationException implements Exception {
  final String failedCommand;
  final String rawResponse;
  Elm327InitializationException(this.failedCommand, this.rawResponse);

  @override
  String toString() =>
      'فشلت تهيئة المحول عند الأمر "$failedCommand" (الرد: ${rawResponse.trim()})';
}

/// الطبقة الوحيدة في التطبيق التي "تعرف" بروتوكول ELM327/OBD2.
/// كل الشاشات تتعامل مع هذا الكلاس فقط (عبر readPid/readRawDtcs/clearDtcs)
/// ولا ترسل أوامر AT أو PID خام مباشرة.
class Elm327Session {
  final Transport transport;
  late final CommandQueue _queue;

  /// سجل تصحيح يحتفظ بآخر 300 أمر/رد خام مع زمن الاستجابة وحالة الخطأ —
  /// يُعرض في شاشة Debug منفصلة لا يراها المستخدم العادي.
  final List<DebugLogEntry> debugLog = [];

  ElmSessionState _state = ElmSessionState.disconnected;
  ElmSessionState get state => _state;
  final StreamController<ElmSessionState> _stateController =
      StreamController<ElmSessionState>.broadcast();
  Stream<ElmSessionState> get stateStream => _stateController.stream;

  /// عدّاد فشل متتالٍ (Timeout/Disconnected فقط) — يُستخدم لتفعيل إعادة
  /// الاتصال التلقائية بدل انتظار المستخدم ليلاحظ توقف البيانات.
  int _consecutiveFailures = 0;
  static const int _maxConsecutiveFailuresBeforeError = 4;
  bool _reconnecting = false;
  bool _disposed = false;

  Elm327Session(this.transport) {
    _queue = CommandQueue(transport);
  }

  bool get isConnected => transport.isConnected;

  void _setState(ElmSessionState s) {
    _state = s;
    if (!_stateController.isClosed) _stateController.add(s);
  }

  Future<String> _send(
    String command, {
    Duration timeout = const Duration(seconds: 4),
    int retries = 1,
  }) async {
    final start = DateTime.now();
    final result =
        await _queue.send(ObdCommand(command, timeout: timeout, maxRetries: retries));
    final latencyMs = DateTime.now().difference(start).inMilliseconds;
    final isError = ObdResponseUtils.hasError(result);
    debugLog.add(DebugLogEntry(DateTime.now(), command, result, latencyMs, isError));
    if (debugLog.length > 300) debugLog.removeAt(0);

    // إعادة اتصال تلقائية: نفرّق بين خطأ بروتوكول عادي (NO DATA لأمر غير
    // مدعوم مثلًا، وهذا طبيعي ومتوقع) وبين انقطاع اتصال فعلي متكرر
    // (TIMEOUT/DISCONNECTED)، ولا نطلق إعادة اتصال إلا في الحالة الثانية.
    final isCommunicationFailure = result == 'TIMEOUT' || result == 'DISCONNECTED';
    if (isCommunicationFailure) {
      _consecutiveFailures++;
      if (_consecutiveFailures >= _maxConsecutiveFailuresBeforeError &&
          _state == ElmSessionState.ready) {
        _setState(ElmSessionState.communicationError);
        _scheduleReconnect();
      }
    } else {
      _consecutiveFailures = 0;
    }

    return result;
  }

  /// محاولات إعادة اتصال محدودة (3 محاولات بفاصل متزايد)، وليست تكرارًا
  /// لا نهائيًا فوريًا يستنزف البطارية أو يُغرق الطابور بأوامر فاشلة.
  void _scheduleReconnect() {
    if (_reconnecting) return;
    _reconnecting = true;
    Future(() async {
      for (int attempt = 1; attempt <= 3; attempt++) {
        if (_disposed) break;
        await Future.delayed(Duration(seconds: 2 * attempt));
        if (_disposed) break;
        final ok = await attemptReconnect();
        if (ok) break;
      }
      _reconnecting = false;
    });
  }

  /// يعيد فتح الاتصال عبر Transport ثم يعيد التهيئة كاملة. يُستدعى تلقائيًا
  /// عند اكتشاف انقطاع متكرر، ويمكن استدعاؤه يدويًا من الواجهة أيضًا لاحقًا.
  Future<bool> attemptReconnect() async {
    _setState(ElmSessionState.reconnecting);
    final connected = await transport.connect();
    if (!connected) {
      _setState(ElmSessionState.communicationError);
      return false;
    }
    try {
      await initialize();
      _consecutiveFailures = 0;
      return true;
    } catch (_) {
      _setState(ElmSessionState.communicationError);
      return false;
    }
  }

  bool _atOkOrNoError(String raw) {
    final upper = raw.toUpperCase();
    if (upper.contains('OK')) return true;
    return !ObdResponseUtils.hasError(raw);
  }

  /// تهيئة المحول خطوة بخطوة مع التحقق من نجاح كل أمر قبل الانتقال للتالي.
  /// عند فشل أي خطوة تُرمى [Elm327InitializationException] بدل الاستمرار
  /// بصمت (كان هذا الخلل في النسخة السابقة).
  Future<void> initialize() async {
    _setState(ElmSessionState.initializing);

    final steps = <InitCommand>[
      InitCommand(
        'ATZ',
        timeout: const Duration(seconds: 2),
        // ATZ يرد بنص تعريفي طويل (اسم الشريحة)؛ يكفي أن يصل أي رد فعلي
        isSuccess: (r) => r.trim().isNotEmpty && r.toUpperCase() != 'TIMEOUT' && r != 'DISCONNECTED',
      ),
      InitCommand('ATE0', isSuccess: _atOkOrNoError),
      InitCommand('ATL0', isSuccess: _atOkOrNoError),
      InitCommand('ATS0', isSuccess: _atOkOrNoError),
      InitCommand('ATH0', isSuccess: _atOkOrNoError),
    ];

    for (final step in steps) {
      final raw = await _send(step.command, timeout: step.timeout);
      if (!step.isSuccess(raw)) {
        _setState(ElmSessionState.communicationError);
        throw Elm327InitializationException(step.command, raw);
      }
      if (step.command == 'ATZ') {
        // بعض نسخ ELM327 تحتاج مهلة قصيرة بعد إعادة الضبط قبل قبول أوامر جديدة
        await Future.delayed(const Duration(milliseconds: 800));
      }
    }

    _setState(ElmSessionState.detectingProtocol);
    // ATSP0 (اختيار البروتوكول تلقائيًا) غالبًا لا يعطي ردًا واضحًا فوريًا؛
    // التحقق الحقيقي من نجاح اختيار البروتوكول يحدث عمليًا مع أول قراءة PID.
    await _send('ATSP0');

    _setState(ElmSessionState.ready);
  }

  Future<num?> readPid(PidDefinition pid) async {
    final raw = await _send(pid.command);
    if (ObdResponseUtils.hasError(raw)) return null;
    final bytes = ObdResponseUtils.extractBytes(raw);
    final expectedPidByte = int.parse(pid.command.substring(2, 4), radix: 16);
    if (bytes.length < 2 || bytes[0] != 0x41 || bytes[1] != expectedPidByte) {
      return null;
    }
    return pid.parse(bytes);
  }

  /// قراءة أكواد الأعطال النشطة حاليًا (Mode 03)
  Future<List<String>> readRawDtcs() async {
    final raw = await _send('03');
    if (ObdResponseUtils.hasError(raw)) return [];
    final bytes = ObdResponseUtils.extractBytes(raw);
    final codes = <String>[];
    if (bytes.isNotEmpty && bytes[0] == 0x43) {
      final data = bytes.sublist(1);
      for (int i = 0; i + 1 < data.length; i += 2) {
        final code = _decodeDtc(data[i], data[i + 1]);
        if (code != null) codes.add(code);
      }
    }
    return codes;
  }

  String? _decodeDtc(int a, int b) {
    if (a == 0 && b == 0) return null;
    const prefixes = ['P', 'C', 'B', 'U'];
    final prefix = prefixes[(a >> 6) & 0x03];
    final digit1 = ((a >> 4) & 0x03).toString();
    final digit2 = (a & 0x0F).toRadixString(16).toUpperCase();
    final rest = b.toRadixString(16).padLeft(2, '0').toUpperCase();
    return '$prefix$digit1$digit2$rest';
  }

  /// مسح أكواد الأعطال وإطفاء ضوء المحرك (Mode 04)
  Future<bool> clearDtcs() async {
    final raw = await _send('04');
    return !ObdResponseUtils.hasError(raw);
  }

  void dispose() {
    _disposed = true;
    _stateController.close();
  }
}
