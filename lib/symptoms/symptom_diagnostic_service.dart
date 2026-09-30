import 'dart:math' as math;
import '../core/elm327_session.dart';
import '../core/pid_registry.dart';
import '../diagnostics/mode06_reader.dart';
import '../telemetry/data_quality.dart';
import 'symptom_coverage.dart';
import 'symptom_models.dart';

class SymptomDiagnosticService {
  final Elm327Session session;
  SymptomDiagnosticService(this.session);

  Future<SymptomReport> run(SymptomDefinition symptom, {void Function(String step)? onStep}) async {
    final evidence = <SymptomEvidence>[];
    final now = DateTime.now();
    onStep?.call('قراءة الأعطال الحالية والمعلّقة والدائمة');
    final active = await session.readRawDtcs();
    final pending = await session.readPendingDtcs();
    final permanent = await session.readPermanentDtcs();
    final codes = {...active, ...pending, ...permanent};
    final related = codes.where(symptom.relatedDtcs.contains).toList();
    evidence.add(SymptomEvidence(title: 'أكواد الأعطال', value: codes.isEmpty ? 'غير متاح: لا توجد أكواد مقروءة' : codes.join(', '), source: ValueSource.genericObd, authority: ValueAuthority.ecuResponse, confidence: codes.isEmpty ? ValueConfidence.unconfirmed : ValueConfidence.high, quality: codes.isEmpty ? ValueQuality.missing : ValueQuality.good, timestamp: now, ageMs: 0, supportingData: 'Active ${active.length}, Pending ${pending.length}, Permanent ${permanent.length}'));

    final samples = <String, List<num>>{};
    await _sample(symptom, OperatingState.idle, symptom.idleSeconds, samples, onStep, evidence);
    if (symptom.loadSeconds > 0) await _sample(symptom, OperatingState.load, symptom.loadSeconds, samples, onStep, evidence);
    onStep?.call('قراءة Mode 06 الخام');
    final mode06 = await Mode06Reader(session).read();
    evidence.add(SymptomEvidence(title: 'Mode 06', value: mode06.status == 'unavailable' ? 'غير متاح' : 'بيانات خام غير مؤكدة', source: ValueSource.genericObd, authority: ValueAuthority.uncertain, confidence: ValueConfidence.unconfirmed, quality: mode06.status == 'unavailable' ? ValueQuality.missing : ValueQuality.degraded, ageMs: 0, supportingData: 'MID/TID يحتاجان تعريف ECU موثق'));

    onStep?.call('تطبيق خمس قواعد عامة');
    final conclusions = <String>[];
    _rule(evidence, conclusions, 'R1', 'وجود DTC مرتبط', related.isNotEmpty, related.join(', '), ValueConfidence.high);
    final ltft = samples['ltft_b1'];
    _rule(evidence, conclusions, 'R2', 'احتمال خليط فقير أو تسريب هواء', ltft != null && _average(ltft) > 10, ltft == null ? 'LTFT غير متاح' : 'LTFT ${_average(ltft).toStringAsFixed(1)}%', ValueConfidence.medium);
    final coolant = samples['coolant_temp'];
    _rule(evidence, conclusions, 'R3', 'المحرك لا يصل لحرارة التشغيل', coolant != null && _average(coolant) < 70, coolant == null ? 'الحرارة غير متاحة' : 'الحرارة ${_average(coolant).toStringAsFixed(1)}°C', ValueConfidence.medium);
    final rpm = samples['rpm'];
    _rule(evidence, conclusions, 'R4', 'عدم استقرار RPM', rpm != null && _stddev(rpm) > 50, rpm == null ? 'RPM غير متاح' : 'الانحراف المعياري ${_stddev(rpm).toStringAsFixed(1)}', ValueConfidence.medium);
    final o2a = samples['o2_b1s1'];
    final o2b = samples['o2_b1s2'];
    _rule(evidence, conclusions, 'R5', 'مقارنة حساسي O2 تحتاج مراجعة', o2a != null && o2b != null && _stddev(o2a) > 0 && _stddev(o2b) > 0, o2a == null || o2b == null ? 'بيانات O2 غير مكتملة' : 'تم جمع بيانات الحساسين', ValueConfidence.low);
    if (conclusions.isEmpty) conclusions.add('لم يظهر دليل كافٍ لتأكيد سبب العرض');
    return SymptomReport(symptom: symptom, timestamp: DateTime.now(), evidence: evidence, conclusions: conclusions, coverage: SymptomCoverage.matrix, uncertainties: const [
      'النتيجة مبنية على Generic OBD وليست Renault-specific',
      'Mode 06 محفوظ كبيانات خام؛ تفسير MID/TID غير مؤكد',
      'الموقع الفيزيائي للبوجيه أو الكويل غير مؤكد',
      'عدم وجود دليل لا يثبت سلامة القطعة',
    ]);
  }

  Future<void> _sample(SymptomDefinition symptom, OperatingState state, int seconds, Map<String, List<num>> samples, void Function(String step)? onStep, List<SymptomEvidence> evidence) async {
    if (seconds <= 0) return;
    onStep?.call('جمع بيانات ${state.name} لمدة $seconds ثانية');
    final started = DateTime.now();
    var count = 0;
    while (DateTime.now().difference(started).inSeconds < seconds) {
      for (final key in symptom.requiredPids) {
        final value = await session.readPid(PidRegistry.byKey(key));
        if (value != null) (samples[key] ??= []).add(value);
      }
      count++;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final elapsed = math.max(1, DateTime.now().difference(started).inMilliseconds) / 1000;
    for (final key in symptom.requiredPids) {
      final values = samples[key];
      final value = values == null || values.isEmpty ? null : _average(values);
      evidence.add(SymptomEvidence(title: '$key (${state.name})', value: value == null ? 'غير متاح: لا توجد عينات كافية' : value.toStringAsFixed(2), source: ValueSource.genericObd, authority: value == null ? ValueAuthority.uncertain : ValueAuthority.ecuResponse, confidence: value == null ? ValueConfidence.unconfirmed : ValueConfidence.high, quality: value == null ? ValueQuality.missing : ValueQuality.good, ageMs: DateTime.now().difference(started).inMilliseconds, rateHz: count / elapsed, state: state, supportingData: '${values?.length ?? 0} عينة'));
    }
  }

  void _rule(List<SymptomEvidence> evidence, List<String> conclusions, String id, String title, bool matched, String support, ValueConfidence confidence) {
    evidence.add(SymptomEvidence(title: id, value: matched ? 'ينطبق: $title' : 'لم ينطبق: $title', source: ValueSource.estimated, authority: ValueAuthority.applicationInference, confidence: matched ? confidence : ValueConfidence.unconfirmed, quality: support.contains('غير متاح') ? ValueQuality.missing : ValueQuality.good, ageMs: 0, supportingData: support));
    if (matched) conclusions.add('$title؛ الدليل: $support');
  }

  double _average(List<num> values) => values.fold<double>(0, (sum, v) => sum + v) / values.length;
  double _stddev(List<num> values) { if (values.length < 2) return 0; final avg = _average(values); final variance = values.fold<double>(0, (sum, v) => sum + (v - avg) * (v - avg)) / values.length; return math.sqrt(variance); }
}
