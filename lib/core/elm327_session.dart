import 'dart:async';
import 'command_queue.dart';
import 'elm_session_state.dart';
import 'init_command.dart';
import 'obd_response_utils.dart';
import 'pid_registry.dart';
import 'raw_capture.dart';
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
  final RawCaptureStore rawCapture;
  late final CommandQueue _queue;

  /// سجل تصحيح يحتفظ بآخر 300 أمر/رد خام مع زمن الاستجابة وحالة الخطأ —
  /// يُعرض في شاشة Debug منفصلة لا يراها المستخدم العادي.
  final List<DebugLogEntry> debugLog = [];

  ElmSessionState _state = ElmSessionState.disconnected;
  ElmSessionState get state => _state;
  Set<int>? _supportedPids;
  Set<int>? get supportedPids => _supportedPids == null ? null : Set.unmodifiable(_supportedPids!);
  final StreamController<ElmSessionState> _stateController =
      StreamController<ElmSessionState>.broadcast();
  Stream<ElmSessionState> get stateStream => _stateController.stream;

  /// عدّاد فشل متتالٍ (Timeout/Disconnected فقط) — يُستخدم لتفعيل إعادة
  /// الاتصال التلقائية بدل انتظار المستخدم ليلاحظ توقف البيانات.
  int _consecutiveFailures = 0;
  static const int _maxConsecutiveFailuresBeforeError = 4;
  bool _reconnecting = false;
  bool _disposed = false;

  Elm327Session(this.transport, {RawCaptureStore? rawCapture})
      : rawCapture = rawCapture ?? RawCaptureStore() {
    _queue = CommandQueue(transport);
  }

  bool get isConnected => transport.isConnected;

  /// Returns whether a PID is advertised by the ECU, or null when the
  /// capability bitmap has not been obtained / does not cover that PID.
  bool? isPidSupported(int pid) {
    final supported = _supportedPids;
    if (supported == null || pid > 0x20) return null;
    return supported.contains(pid);
  }

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
    rawCapture.record(RawCaptureEntry(
      timestamp: DateTime.now(),
      transport: transport.runtimeType.toString(),
      command: command,
      rawResponse: result,
      latencyMs: latencyMs,
      isError: isError,
    ));
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

    // Capability evidence for the first standard PID window. This is
    // intentionally advisory: unsupported/unknown windows remain readable
    // as UNCONFIRMED rather than being presented as guaranteed.
    _supportedPids = await _readSupportedPidWindow('0100', 0x00);

    _setState(ElmSessionState.ready);
  }

  Future<Set<int>?> _readSupportedPidWindow(String command, int basePid) async {
    final raw = await _send(command);
    if (ObdResponseUtils.hasError(raw)) return null;
    final bytes = ObdResponseUtils.extractBytes(raw);
    if (bytes.length < 6 || bytes[0] != 0x41 || bytes[1] != basePid) return null;
    final supported = <int>{};
    for (var byteIndex = 0; byteIndex < 4; byteIndex++) {
      final bitmap = bytes[byteIndex + 2];
      for (var bit = 0; bit < 8; bit++) {
        if ((bitmap & (1 << (7 - bit))) != 0) {
          supported.add(basePid + (byteIndex * 8) + bit + 1);
        }
      }
    }
    return supported;
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
  Future<List<String>> readRawDtcs() => _readDtcs('03', 0x43);

  /// قراءة أكواد الأعطال المعلّقة (Mode 07).
  Future<List<String>> readPendingDtcs() => _readDtcs('07', 0x47);

  /// قراءة أكواد الأعطال الدائمة (Mode 0A).
  Future<List<String>> readPermanentDtcs() => _readDtcs('0A', 0x4A);

  Future<List<String>> _readDtcs(String command, int responseMode) async {
    final raw = await _send(command);
    if (ObdResponseUtils.hasError(raw)) return [];
    final bytes = ObdResponseUtils.extractBytes(raw);
    final codes = <String>[];
    if (bytes.isNotEmpty && bytes[0] == responseMode) {
      final data = bytes.sublist(1);
      for (int i = 0; i + 1 < data.length; i += 2) {
        final code = _decodeDtc(data[i], data[i + 1]);
        if (code != null) codes.add(code);
      }
    }
    return codes;
  }

  /// قراءة VIN القياسي عبر Mode 09 PID 02 إن كان المحول/ECU يدعمه.
  /// تُرجع null عند عدم الدعم أو عند عدم اكتمال رد ASCII بطول VIN قياسي.
  Future<String?> readVin() async {
    final raw = await _send('0902');
    if (ObdResponseUtils.hasError(raw)) return null;
    final bytes = ObdResponseUtils.extractBytes(raw);
    if (bytes.length < 3 || bytes[0] != 0x49 || bytes[1] != 0x02) return null;

    var data = bytes.sublist(2);
    if (data.isNotEmpty && data.first <= 0x02) data = data.sublist(1);
    final vin = String.fromCharCodes(
      data.where((b) => b >= 0x20 && b <= 0x7E),
    ).replaceAll(RegExp(r'\s+'), '');
    return RegExp(r'^[A-HJ-NPR-Z0-9]{17}$').hasMatch(vin) ? vin : null;
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
