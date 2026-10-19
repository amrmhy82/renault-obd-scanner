import '../core/elm327_session.dart';
import '../core/obd_response_utils.dart';
import '../core/pid_registry.dart';

enum QuickScanSeverity { ok, attention, unavailable }

class QuickScanItem {
  final String title;
  final String value;
  final String detail;
  final QuickScanSeverity severity;
  const QuickScanItem({required this.title, required this.value, required this.detail, required this.severity});
  Map<String, Object?> toJson() => {'title': title, 'value': value, 'detail': detail, 'severity': severity.name};
}

class QuickScanReport {
  final DateTime timestamp;
  final String? vin;
  final List<String> activeDtcs;
  final List<String> pendingDtcs;
  final List<String> permanentDtcs;
  final List<QuickScanItem> items;
  final List<String> recommendations;
  final String summary;

  const QuickScanReport({required this.timestamp, required this.vin, required this.activeDtcs, required this.pendingDtcs, required this.permanentDtcs, required this.items, required this.recommendations, required this.summary});

  Map<String, Object?> toJson() => {
        'timestamp': timestamp.toIso8601String(), 'vin': vin,
        'dtcs': {'active': activeDtcs, 'pending': pendingDtcs, 'permanent': permanentDtcs},
        'items': items.map((i) => i.toJson()).toList(), 'recommendations': recommendations, 'summary': summary,
      };
}

class QuickScanService {
  final Elm327Session session;
  QuickScanService(this.session);

  Future<QuickScanReport> run({void Function(String step)? onStep}) async {
    onStep?.call('قراءة VIN');
    final vin = await session.readVin();
    onStep?.call('قراءة الأعطال');
    final active = await session.readRawDtcs();
    final pending = await session.readPendingDtcs();
    final permanent = await session.readPermanentDtcs();
    final items = <QuickScanItem>[];
    final recommendations = <String>[];

    if (active.isEmpty && pending.isEmpty && permanent.isEmpty) {
      items.add(const QuickScanItem(title: 'أكواد الأعطال', value: 'لا توجد أكواد مقروءة', detail: 'Mode 03/07/0A', severity: QuickScanSeverity.ok));
    } else {
      final codes = {...active, ...pending, ...permanent};
      items.add(QuickScanItem(title: 'أكواد الأعطال', value: '${codes.length} كود', detail: codes.join(', '), severity: QuickScanSeverity.attention));
      recommendations.add('افتح شاشة الأعطال لقراءة التفاصيل قبل مسح أي كود.');
    }

    onStep?.call('قراءة حالة الجاهزية');
    final readiness = await session.readReadiness();
    if (readiness == null) {
      items.add(const QuickScanItem(title: 'جاهزية أنظمة الانبعاثات', value: 'غير متاحة', detail: 'لم يرد ECU على 0101', severity: QuickScanSeverity.unavailable));
    } else {
      // Mode 01 PID 01 returns A/B/C/D: A contains MIL and stored DTC count.
      // The previous code read MIL from C, which could report a false warning.
      final mil = (readiness[0] & 0x80) != 0;
      final storedDtcCount = readiness[0] & 0x7F;
      final detail = 'MIL: ${mil ? "مضيئة" : "منطفئة"} • عدد الأكواد في ECU: $storedDtcCount • بيانات الجاهزية الخام: ${readiness.map((b) => b.toRadixString(16).padLeft(2, "0").toUpperCase()).join(" ")}';
      final severity = mil || storedDtcCount > 0 ? QuickScanSeverity.attention : QuickScanSeverity.ok;
      items.add(QuickScanItem(title: 'جاهزية أنظمة الانبعاثات', value: mil ? 'تحتاج متابعة' : 'لا توجد إشارة MIL', detail: detail, severity: severity));
      if (!mil && storedDtcCount == 0) recommendations.add('لا توجد إشارة MIL أو أكواد مخزنة وفق رد 0101؛ تبقى اختبارات الجاهزية التفصيلية مرتبطة بتعريف ECU.');
    }

    onStep?.call('قراءة القياسات الأساسية');
    for (final key in const ['rpm', 'speed', 'coolant_temp', 'engine_load', 'map', 'stft_b1', 'ltft_b1']) {
      final pid = PidRegistry.byKey(key);
      final value = await session.readPid(pid);
      if (value == null) {
        items.add(QuickScanItem(title: pid.nameAr, value: 'غير متاحة', detail: '${pid.command} • لا يوجد رد', severity: QuickScanSeverity.unavailable));
      } else {
        items.add(QuickScanItem(title: pid.nameAr, value: '${_format(value)} ${pid.unit}', detail: 'قراءة مباشرة من ECU عبر ${pid.command}', severity: QuickScanSeverity.ok));
      }
    }
    onStep?.call('قراءة جهد محول ELM327');
    final adapterVoltage = await session.readAdapterVoltage();
    items.add(QuickScanItem(
      title: 'جهد المحول من منفذ OBD',
      value: adapterVoltage == null ? 'غير متاح' : '${_format(adapterVoltage)} V',
      detail: adapterVoltage == null ? 'ATRV • لم يرد المحول' : 'قراءة من شريحة ELM327 عبر ATRV، وليست قياسًا مباشرًا مضمونًا للبطارية',
      severity: adapterVoltage == null ? QuickScanSeverity.unavailable : QuickScanSeverity.ok,
    ));

    onStep?.call('قراءة Freeze Frame');
    final freezeFrame = await session.readFreezeFrameRaw();
    items.add(QuickScanItem(title: 'Freeze Frame', value: freezeFrame == null ? 'غير متاح' : 'بيانات خام محفوظة', detail: freezeFrame == null ? 'لم يرد ECU على 0200' : 'يُعرض خامًا دون تفسير Renault-specific', severity: freezeFrame == null ? QuickScanSeverity.unavailable : QuickScanSeverity.attention));
    if (freezeFrame != null) recommendations.add('Freeze Frame متاح؛ راجعه مع كود العطل لمعرفة ظروف تسجيله.');

    final summary = active.isNotEmpty ? 'توجد أعطال نشطة تحتاج فحصًا' : pending.isNotEmpty ? 'توجد أعطال معلّقة تحتاج متابعة' : 'لم تظهر أكواد أعطال في الفحص العام';
    return QuickScanReport(timestamp: DateTime.now(), vin: vin, activeDtcs: active, pendingDtcs: pending, permanentDtcs: permanent, items: items, recommendations: recommendations, summary: summary);
  }

  String _format(num value) => value == value.roundToDouble() ? value.round().toString() : value.toStringAsFixed(2);
}
