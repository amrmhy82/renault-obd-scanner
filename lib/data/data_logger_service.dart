import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../core/pid_registry.dart';
import '../telemetry/vehicle_state.dart';

/// تسجيل مستمر لحالة السيارة في ملف CSV، بمعدل ثابت (1 Hz افتراضيًا) بدل
/// الكتابة مع كل وصول تحديث PID (غير منتظم ويؤدي لصفوف مكرّرة زائدة).
///
/// الفرق عن TripLogService:
///   - TripLogService يحفظ 3 قيم فقط (rpm/speed/coolant) لأجل الرسوم البيانية
///     داخل SharedPreferences، بحجم صغير وثابت.
///   - DataLoggerService يحفظ **كل** PID في PidRegistry، بمعدل عالٍ ومستمر،
///     في ملف CSV على القرص. كل جلسة اتصال تُنتج ملفًا جديدًا.
///
/// نقطة مهمة (تصحيح عن نسخة أولى): لا نكتفي بحفظ "آخر قيمة معروفة" لكل عمود
/// إلى الأبد، لأن PID قد يتوقف عن الرد (فصل مؤقت، أو عدم دعم من وحدة الحقن)
/// فتتكرر القيمة القديمة في كل صف تالٍ وكأنها ما زالت صحيحة — وهذا مضلّل في
/// تطبيق تشخيصي. لذا نتتبّع زمن آخر تحديث فعلي لكل عمود، ونكتب خانة فارغة
/// بدل القيمة لو تجاوز عمرها حدًّا معقولًا (ضعف ونصف فاصل فئة الاستقصاء).
class DataLoggerService {
  static const Duration _flushInterval = Duration(seconds: 3);
  static const int _sampleRateHz = 1;

  /// حد "انتهاء الصلاحية" لكل فئة استقصاء — إن لم يصل تحديث جديد لعمود
  /// خلال هذه المدة، تُعتبر قيمته المخزَّنة قديمة ولا تُكتب كأنها حالية.
  static const Map<PollClass, Duration> _stalenessThresholds = {
    PollClass.fast: Duration(seconds: 2),
    PollClass.medium: Duration(seconds: 6),
    PollClass.slow: Duration(seconds: 25),
  };

  File? _currentFile;
  IOSink? _sink;
  Timer? _writeTimer;
  Timer? _flushTimer;
  DateTime? _sessionStart;
  List<String> _columns = [];
  final Map<String, num?> _latest = {};
  final Map<String, DateTime> _lastUpdated = {};
  int _rowCount = 0;
  bool _active = false;
  bool _writePending = false;

  bool get isActive => _active;
  int get rowCount => _rowCount;
  DateTime? get sessionStart => _sessionStart;
  File? get currentFile => _currentFile;

  /// يبدأ جلسة تسجيل جديدة — يُستدعى مرة واحدة بعد نجاح الاتصال بالسيارة.
  Future<void> start() async {
    if (_active) return;
    _active = true;
    _sessionStart = DateTime.now();
    _columns = PidRegistry.all.map((p) => p.key).toList();
    _latest.clear();
    _lastUpdated.clear();
    for (final c in _columns) {
      _latest[c] = null;
    }
    _rowCount = 0;

    try {
      final dir = await _logsDirectory();
      final ts = _sessionStart!.toIso8601String().replaceAll(':', '-').split('.').first;
      _currentFile = File('${dir.path}/obd_log_$ts.csv');
      _sink = _currentFile!.openWrite(mode: FileMode.write);

      // BOM يضمن قراءة Excel للـ CSV بترميز UTF-8 بشكل صحيح
      _sink!.add([0xEF, 0xBB, 0xBF]);
      _sink!.writeln(['timestamp_iso', 'elapsed_ms', ..._columns].join(','));

      _writeTimer = Timer.periodic(
        Duration(milliseconds: 1000 ~/ _sampleRateHz),
        (_) => _writeRow(),
      );
      _flushTimer = Timer.periodic(_flushInterval, (_) => _flush());
    } catch (_) {
      _active = false;
    }
  }

  /// يُستدعى من DashboardScreen بعد كل تحديث VehicleState. يحدّث القيم
  /// الأخيرة وزمن وصولها فقط؛ الكتابة الفعلية تحدث في المؤقت (1 Hz).
  void record(VehicleState state) {
    if (!_active) return;
    final now = DateTime.now();
    for (final key in _columns) {
      final v = state[key];
      if (v != null) {
        _latest[key] = v;
        _lastUpdated[key] = now;
      }
    }
  }

  void _writeRow() {
    final sink = _sink;
    final start = _sessionStart;
    if (sink == null || start == null) return;
    final now = DateTime.now();
    final elapsedMs = now.difference(start).inMilliseconds;

    final cells = PidRegistry.all.map((pid) {
      final lastSeen = _lastUpdated[pid.key];
      if (lastSeen == null) return ''; // لم تصل أي قيمة بعد لهذا العمود إطلاقًا
      final threshold = _stalenessThresholds[pid.pollClass]!;
      if (now.difference(lastSeen) > threshold) {
        return ''; // القيمة قديمة/متجمّدة — لا نكتبها كأنها حالية
      }
      return _fmt(_latest[pid.key]);
    });

    try {
      sink.writeln([now.toIso8601String(), elapsedMs.toString(), ...cells].join(','));
      _rowCount++;
      _writePending = true;
    } catch (_) {
      // تجاهل أخطاء الكتابة الطفيفة (نادر جدًا)
    }
  }

  String _fmt(num? v) {
    if (v == null) return '';
    if (v is int) return v.toString();
    if (v == v.truncate()) return v.truncate().toString();
    return v.toStringAsFixed(3);
  }

  Future<void> _flush() async {
    final sink = _sink;
    if (!_writePending || sink == null) return;
    try {
      await sink.flush();
      _writePending = false;
    } catch (_) {}
  }

  /// يُستدعى من dispose لوحة البيانات — يوقف المؤقتات، يفرّغ الذاكرة إلى
  /// القرص، ويغلق الملف. آمن للاستدعاء أكثر من مرة.
  Future<void> stop() async {
    if (!_active) return;
    _active = false;
    _writeTimer?.cancel();
    _writeTimer = null;
    _flushTimer?.cancel();
    _flushTimer = null;
    try {
      await _sink?.flush();
    } catch (_) {}
    try {
      await _sink?.close();
    } catch (_) {}
    _sink = null;
  }

  Future<Directory> _logsDirectory() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/obd_logs');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// الأحدث أولًا حسب الاسم (الاسم يبدأ بالتاريخ ISO).
  Future<List<File>> listLogs() async {
    try {
      final dir = await _logsDirectory();
      final files = <File>[];
      await for (final entity in dir.list()) {
        if (entity is File && entity.path.endsWith('.csv')) files.add(entity);
      }
      files.sort((a, b) => b.path.compareTo(a.path));
      return files;
    } catch (_) {
      return [];
    }
  }

  Future<void> deleteLog(File f) async {
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  Future<void> deleteAllLogs() async {
    final files = await listLogs();
    for (final f in files) {
      await deleteLog(f);
    }
  }
}
