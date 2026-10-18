import '../core/elm327_session.dart';
import '../core/obd_response_utils.dart';
import '../core/pid_registry.dart';

enum CertificationStatus { pass, fail, skipped }

class CertificationResult {
  final String id;
  final String title;
  final CertificationStatus status;
  final String details;
  final DateTime timestamp;

  CertificationResult({
    required this.id,
    required this.title,
    required this.status,
    required this.details,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'status': status.name,
        'details': details,
        'timestamp': timestamp.toIso8601String(),
      };
}

class CertificationReport {
  final DateTime startedAt;
  final DateTime completedAt;
  final List<CertificationResult> results;

  CertificationReport({
    required this.startedAt,
    required this.completedAt,
    required this.results,
  });

  Map<String, Object?> toJson() => {
        'startedAt': startedAt.toIso8601String(),
        'completedAt': completedAt.toIso8601String(),
        'summary': {
          'pass': results.where((r) => r.status == CertificationStatus.pass).length,
          'fail': results.where((r) => r.status == CertificationStatus.fail).length,
          'skipped': results.where((r) => r.status == CertificationStatus.skipped).length,
        },
        'tests': results.map((r) => r.toJson()).toList(),
      };
}

class CertificationService {
  final Elm327Session session;
  CertificationService(this.session);

  Future<CertificationReport> run() async {
    final started = DateTime.now();
    final results = <CertificationResult>[];
    void add(String id, String title, CertificationStatus status, String details) {
      results.add(CertificationResult(id: id, title: title, status: status, details: details));
    }

    add('transport', 'اتصال النقل', session.isConnected ? CertificationStatus.pass : CertificationStatus.fail,
        session.isConnected ? 'المحول متصل' : 'لا يوجد اتصال');
    add('session', 'حالة جلسة ELM327', session.state.name == 'ready' ? CertificationStatus.pass : CertificationStatus.fail,
        'الحالة: ${session.state.name}');
    add('raw_capture', 'تسجيل Raw Capture', session.rawCapture.entries.isNotEmpty ? CertificationStatus.pass : CertificationStatus.skipped,
        session.rawCapture.entries.isNotEmpty ? 'تم تسجيل أوامر ووردود' : 'لا توجد عينة بعد');

    if (!session.isConnected || session.state.name != 'ready') {
      for (final item in const [
        ('pid_bitmap', '0100 Supported PIDs'),
        ('rpm', 'قراءة RPM عبر 010C'),
        ('speed', 'قراءة السرعة عبر 010D'),
        ('coolant', 'قراءة حرارة سائل التبريد عبر 0105'),
        ('active_dtcs', 'قراءة الأعطال النشطة Mode 03'),
        ('pending_dtcs', 'قراءة الأعطال المعلّقة Mode 07'),
        ('permanent_dtcs', 'قراءة الأعطال الدائمة Mode 0A'),
        ('vin', 'قراءة VIN عبر 0902'),
        ('parser', 'تحليل رد ATS0 بدون مسافات'),
        ('quality', 'بيانات الجودة والعمر والمعدل'),
        ('audit', 'سجل تدقيق العمليات'),
        ('read_only', 'الوضع الافتراضي للقراءة فقط'),
      ]) {
        add(item.$1, item.$2, CertificationStatus.skipped, 'يتطلب اتصالًا فعليًا ومحولًا مهيأً');
      }
      return CertificationReport(startedAt: started, completedAt: DateTime.now(), results: results);
    }

    add('pid_bitmap', '0100 Supported PIDs', session.supportedPids != null ? CertificationStatus.pass : CertificationStatus.fail,
        session.supportedPids == null ? 'لم تصل خريطة الدعم' : '${session.supportedPids!.length} PID');
    await _pid(results, 'rpm', 'قراءة RPM عبر 010C', 'rpm');
    await _pid(results, 'speed', 'قراءة السرعة عبر 010D', 'speed');
    await _pid(results, 'coolant', 'قراءة حرارة سائل التبريد عبر 0105', 'coolant_temp');
    await _dtc(results, 'active_dtcs', 'قراءة الأعطال النشطة Mode 03', '03', 0x43, session.readRawDtcs);
    await _dtc(results, 'pending_dtcs', 'قراءة الأعطال المعلّقة Mode 07', '07', 0x47, session.readPendingDtcs);
    await _dtc(results, 'permanent_dtcs', 'قراءة الأعطال الدائمة Mode 0A', '0A', 0x4A, session.readPermanentDtcs);
    final vin = await session.readVin();
    add('vin', 'قراءة VIN عبر 0902', vin != null ? CertificationStatus.pass : CertificationStatus.skipped,
        vin ?? 'غير مدعوم أو لم يرد ECU');
    final parser = _parserSelfTest();
    add('parser', 'تحليل رد ATS0 بدون مسافات', parser ? CertificationStatus.pass : CertificationStatus.fail,
        parser ? 'نجح اختبار الرد المتصل والمفصول: 410C0000 و 41 0C 00 00' : 'فشل اختبار تفكيك بايتات الرد');
    add('quality', 'بيانات الجودة والعمر والمعدل', CertificationStatus.skipped,
        'يتطلب الاختبار تشغيل LiveTelemetryService واستلام VehicleState فعلي');
    add('audit', 'سجل تدقيق العمليات', CertificationStatus.skipped,
        'يتطلب تشغيل DtcHistoryRepository وتسجيل عملية DTC فعلية');
    final destructive = session.rawCapture.entries.any((e) => e.command.toUpperCase() == '04');
    add('read_only', 'الوضع الافتراضي للقراءة فقط', destructive ? CertificationStatus.fail : CertificationStatus.pass,
        destructive ? 'تم العثور على أمر مسح DTC في جلسة الاعتماد' : 'لم يُرسل أمر تغيير أو مسح أثناء الاعتماد');
    return CertificationReport(startedAt: started, completedAt: DateTime.now(), results: results);
  }

  Future<void> _pid(List<CertificationResult> out, String id, String title, String key) async {
    final value = await session.readPid(PidRegistry.byKey(key));
    out.add(CertificationResult(id: id, title: title, status: value == null ? CertificationStatus.fail : CertificationStatus.pass,
        details: value == null ? 'لم تصل قراءة صحيحة' : 'قيمة: $value'));
  }

  Future<void> _dtc(List<CertificationResult> out, String id, String title, String command, int responseMode, Future<List<String>> Function() read) async {
    final codes = await read();
    final capture = session.rawCapture.entries.reversed.where((e) => e.command.toUpperCase() == command).firstOrNull;
    if (capture == null) {
      out.add(CertificationResult(id: id, title: title, status: CertificationStatus.fail, details: 'لم يُسجل رد الأمر $command'));
      return;
    }
    final bytes = ObdResponseUtils.extractBytes(capture.rawResponse);
    final valid = !capture.isError && bytes.isNotEmpty && bytes.first == responseMode;
    out.add(CertificationResult(id: id, title: title, status: valid ? CertificationStatus.pass : CertificationStatus.fail,
        details: valid ? '${codes.length} كود • رد صالح' : 'الرد غير صالح أو يحتوي خطأ: ${capture.rawResponse.trim()}'));
  }

  bool _parserSelfTest() {
    final compact = ObdResponseUtils.extractBytes('410C0000');
    final spaced = ObdResponseUtils.extractBytes('41 0C 00 00');
    return compact.length == 4 && spaced.length == 4 && compact.join(',') == spaced.join(',') && compact[0] == 0x41 && compact[1] == 0x0C;
  }
}
