import '../core/elm327_session.dart';
import '../core/raw_capture.dart';
import '../reports/report_archive_service.dart';

/// Collects only read-only, standard OBD evidence that can guide later
/// Renault-specific work. It never probes arbitrary CAN IDs or write services.
class RenaultResourceCaptureService {
  static const standardReadOnlyCommands = <String>{
    'ATI', 'AT@1', 'ATDPN', 'ATDP', '0902', 'ATRV', '0100', '0120', '0140',
    '03', '07', '0A', '0101', '0600', '06', '0200',
  };

  final Elm327Session session;
  RenaultResourceCaptureService(this.session);

  Future<Map<String, Object?>> run({void Function(String step)? onStep}) async {
    const captureVersion = '2.0';
    // RawCaptureStore is bounded and can evict old entries while the session
    // is running. A starting index therefore becomes invalid at capacity;
    // timestamps keep the resource capture isolated even after rollover.
    final captureStartedAt = DateTime.now();
    List<RawCaptureEntry> captureEntries() => session.rawCapture.entries
        .where((entry) => !entry.timestamp.isBefore(captureStartedAt))
        .toList();
    final report = <String, Object?>{
      'captureVersion': captureVersion,
      'capturedAt': DateTime.now().toIso8601String(),
      'status': 'partial',
      'scope': 'generic_obd_read_only_resource_capture',
      'safety': {
        'readOnly': true,
        'writeServicesSent': <String>[],
        'arbitraryCanProbing': false,
        'note': 'لا يحتوي هذا الملف على تعريف Renault مؤكد، ولا يثبت الوصول إلى CVT/ABS/Airbag.',
      },
      'commands': <String>[],
      'requiredResourcesForLater': const [
        'ECU identification من DDT4All أو PyRen في جلسة منفصلة',
        'CAN request/response IDs الموثقة لكل وحدة',
        'Renault DID/TID definitions المتوافقة مع ECU الفعلي',
        'عينة Raw Capture مرتبطة بالـ VIN والمحول والبروتوكول',
      ],
    };
    Future<void> checkpoint() async {
      report['updatedAt'] = DateTime.now().toIso8601String();
      final entries = captureEntries();
      report['rawCaptureEntries'] = entries.length;
      report['sessionRawCaptureEntries'] = session.rawCapture.entries.length;
      report['rawCapture'] = entries.map((entry) => entry.toJson()).toList();
      report['commands'] = entries.map((entry) => entry.command).toSet().toList();
      await ReportArchiveService.instance.writePartialJson('renault_resource_capture', report);
    }

    onStep?.call('قراءة هوية المحول والبروتوكول');
    report['adapter'] = await session.readAdapterInfo();
    report['protocolBefore'] = await session.readProtocolInfo();
    await checkpoint();

    onStep?.call('قراءة هوية السيارة وعينات الجهد');
    final vin = await session.readVin();
    final voltageSamples = <num>[];
    for (var i = 0; i < 3; i++) {
      final voltage = await session.readAdapterVoltage();
      if (voltage != null) voltageSamples.add(voltage);
      if (i < 2) await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    report['vehicle'] = {'vin': vin};
    report['adapterVoltage'] = {
      'samples': voltageSamples,
      'start': voltageSamples.isEmpty ? null : voltageSamples.first,
      'end': voltageSamples.isEmpty ? null : voltageSamples.last,
      'meaning': 'جهد يقيسه المحول عند منفذ OBD، وليس قياس بطارية مضمونًا',
    };
    await checkpoint();

    onStep?.call('قراءة خريطة Supported PIDs');
    final supported = session.supportedPids == null
        ? <int>[]
        : (session.supportedPids!.toList()..sort());
    report['supportedPids'] = supported;
    await checkpoint();

    onStep?.call('قراءة الأعطال والجاهزية');
    final active = await session.readRawDtcs();
    final pending = await session.readPendingDtcs();
    final permanent = await session.readPermanentDtcs();
    final readiness = await session.readReadiness();
    report['dtcs'] = {'active': active, 'pending': pending, 'permanent': permanent};
    report['readinessBytes'] = readiness;
    await checkpoint();

    onStep?.call('حفظ Mode 06 وFreeze Frame الخام');
    final mode06Supported = await session.readMode06SupportedRaw();
    final mode06 = await session.readMode06Raw();
    final freezeFrame = await session.readFreezeFrameRaw();
    report['mode06'] = {
      'supportedRaw': mode06Supported,
      'dataRaw': mode06,
      'interpretation': 'خام فقط؛ لا تُنسب TID/MID أو أسطوانة دون تعريف ECU موثق',
    };
    report['freezeFrame'] = {
      'raw': freezeFrame,
      'associatedActiveDtc': active.isEmpty ? null : active.first,
    };
    report['protocolAfter'] = await session.readProtocolInfo();
    report['status'] = 'complete';
    report['completedAt'] = DateTime.now().toIso8601String();
    await checkpoint();
    await ReportArchiveService.instance.recordJson('renault_resource_capture', report);
    await ReportArchiveService.instance.removePartialJson('renault_resource_capture');
    return report;
  }
}
