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
    evidence.add(SymptomEvidence(title: 'أكواد الأعطال', value: codes.isEmpty ? 'لا توجد أكواد مقروءة' : codes.join(', '), source: ValueSource.genericObd, authority: ValueAuthority.ecuResponse, confidence: related.isNotEmpty ? ValueConfidence.high : ValueConfidence.unconfirmed, quality: codes.isEmpty ? ValueQuality.missing : ValueQuality.good, timestamp: now, ageMs: 0, supportingData: 'Active ${active.length}, Pending ${pending.length}, Permanent ${permanent.length}'));

    final samples = <OperatingState, Map<String, List<num>>>{};
    await _sample(symptom, OperatingState.idle, symptom.idleSeconds, samples, onStep, evidence);
    if (symptom.loadSeconds > 0) await _sample(symptom, OperatingState.load, symptom.loadSeconds, samples, onStep, evidence);
    onStep?.call('قراءة Mode 06 الخام');
    final mode06 = await Mode06Reader(session).read();
    evidence.add(SymptomEvidence(title: 'Mode 06', value: mode06.status == 'unavailable' ? 'غير متاح' : 'بيانات خام غير مؤكدة', source: ValueSource.genericObd, authority: ValueAuthority.uncertain, confidence: ValueConfidence.unconfirmed, quality: mode06.status == 'unavailable' ? ValueQuality.missing : ValueQuality.degraded, ageMs: 0, supportingData: 'MID/TID يحتاجان تعريف ECU موثق'));

    onStep?.call('تحليل الأدلة الخاصة بالعرض');
    final conclusions = <String>[];
    for (final id in symptom.ruleIds) {
      applyRule(id, symptom, codes, related, samples, evidence, conclusions);
    }
    if (conclusions.isEmpty) conclusions.add('لم يظهر دليل كافٍ لتأكيد سبب العرض؛ يلزم تسجيل قيادة أو فحص متخصص حسب الحالة');
    return SymptomReport(symptom: symptom, timestamp: DateTime.now(), evidence: evidence, conclusions: conclusions, recommendations: symptom.recommendations, coverage: SymptomCoverage.matrix, uncertainties: const [
      'النتيجة مبنية على Generic OBD وليست Renault-specific',
      'حالة التشغيل مبنية على نمط العينة (خمول/حمل) وليست إثباتًا لظروف القيادة الفعلية',
      'Mode 06 محفوظ كبيانات خام؛ تفسير MID/TID غير مؤكد',
      'الموقع الفيزيائي للبوجيه أو الكويل غير مؤكد، ولا يثبت التقرير عطل CVT أو ABS أو Airbag',
      'عدم وجود دليل لا يثبت سلامة القطعة',
    ]);
  }

  Future<void> _sample(SymptomDefinition symptom, OperatingState state, int seconds, Map<OperatingState, Map<String, List<num>>> samples, void Function(String step)? onStep, List<SymptomEvidence> evidence) async {
    if (seconds <= 0) return;
    onStep?.call('جمع بيانات ${state.name} لمدة $seconds ثانية');
    final started = DateTime.now();
    final bucket = samples.putIfAbsent(state, () => <String, List<num>>{});
    var count = 0;
    while (DateTime.now().difference(started).inSeconds < seconds) {
      for (final key in symptom.requiredPids) {
        final value = await session.readPid(PidRegistry.byKey(key));
        if (value != null) (bucket[key] ??= []).add(value);
      }
      count++;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final elapsed = math.max(1, DateTime.now().difference(started).inMilliseconds) / 1000;
    for (final key in symptom.requiredPids) {
      final values = bucket[key];
      final value = values == null || values.isEmpty ? null : _average(values);
      evidence.add(SymptomEvidence(title: '$key (${state.name})', value: value == null ? 'غير متاح: لا توجد عينات كافية' : value.toStringAsFixed(2), source: ValueSource.genericObd, authority: value == null ? ValueAuthority.uncertain : ValueAuthority.ecuResponse, confidence: value == null ? ValueConfidence.unconfirmed : ValueConfidence.high, quality: value == null ? ValueQuality.missing : ValueQuality.good, ageMs: DateTime.now().difference(started).inMilliseconds, rateHz: count / elapsed, state: state, supportingData: '${values?.length ?? 0} عينة'));
    }
  }

  /// Applies one rule to a supplied snapshot. Kept public so automated tests
  /// can verify positive and negative cases without waiting for a live car.
  void applyRule(String id, SymptomDefinition symptom, Set<String> codes, List<String> related, Map<OperatingState, Map<String, List<num>>> samples, List<SymptomEvidence> evidence, List<String> conclusions) {
    final all = <String, List<num>>{};
    for (final bucket in samples.values) {
      for (final entry in bucket.entries) (all[entry.key] ??= []).addAll(entry.value);
    }
    final idle = samples[OperatingState.idle] ?? const <String, List<num>>{};
    bool matched = false;
    var support = 'لا توجد بيانات كافية';
    var title = id;
    var confidence = ValueConfidence.medium;
    switch (id) {
      case 'DTC': matched = related.isNotEmpty; support = related.isEmpty ? (codes.isEmpty ? 'لم تصل أكواد من ECU' : 'لا يوجد كود مرتبط ضمن ${codes.join(', ')}') : related.join(', '); title = 'وجود كود مرتبط بالعرض'; confidence = ValueConfidence.high;
      case 'RPM_UNSTABLE': matched = _stddev(all['rpm']) > 50; support = _metric(all['rpm'], 'RPM'); title = 'عدم استقرار RPM';
      case 'RPM_ZERO': matched = _averageOr(all['rpm'], -1) == 0; support = _metric(all['rpm'], 'RPM'); title = 'وجود عينة RPM تساوي صفرًا'; confidence = ValueConfidence.low;
      case 'LEAN': matched = _averageOr(all['ltft_b1'], 0) > 10 || _averageOr(all['stft_b1'], 0) > 10; support = 'STFT ${_averageOr(all['stft_b1'], double.nan).toStringAsFixed(1)}%, LTFT ${_averageOr(all['ltft_b1'], double.nan).toStringAsFixed(1)}%'; title = 'مؤشر خليط فقير أو تسريب هواء';
      case 'LEAN_IDLE': matched = _averageOr(idle['ltft_b1'], 0) > 10 || _averageOr(idle['stft_b1'], 0) > 10; support = 'قراءة الخمول: ${_metric(idle['ltft_b1'], 'LTFT')}'; title = 'مؤشر خليط فقير أثناء الخمول';
      case 'RICH': matched = _averageOr(all['ltft_b1'], 0) < -10 || _averageOr(all['stft_b1'], 0) < -10; support = 'STFT ${_averageOr(all['stft_b1'], double.nan).toStringAsFixed(1)}%, LTFT ${_averageOr(all['ltft_b1'], double.nan).toStringAsFixed(1)}%'; title = 'مؤشر خليط غني';
      case 'COOLANT_LOW': matched = _averageOr(all['coolant_temp'], 999) < 70; support = _metric(all['coolant_temp'], 'حرارة سائل التبريد'); title = 'المحرك لا يصل لحرارة التشغيل';
      case 'COOLANT_HIGH': matched = _averageOr(all['coolant_temp'], -999) >= 105; support = _metric(all['coolant_temp'], 'حرارة سائل التبريد'); title = 'حرارة مرتفعة تستحق التوقف والفحص'; confidence = ValueConfidence.high;
      case 'COOLANT_RISING': matched = _range(all['coolant_temp']) >= 8; support = _metric(all['coolant_temp'], 'مدى الحرارة'); title = 'ارتفاع ملحوظ في حرارة سائل التبريد';
      case 'COOLANT_IAT_MISMATCH': matched = (_averageOr(all['coolant_temp'], double.nan) - _averageOr(all['iat'], double.nan)).abs() > 15; support = 'فرق الحرارة ${(_averageOr(all['coolant_temp'], double.nan) - _averageOr(all['iat'], double.nan)).abs().toStringAsFixed(1)}°C'; title = 'عدم تطابق حرارة التبريد والهواء'; confidence = ValueConfidence.low;
      case 'MAP_IDLE': matched = _averageOr(idle['map'], 0) > 60; support = _metric(idle['map'], 'MAP'); title = 'ضغط سحب مرتفع نسبيًا أثناء الخمول'; confidence = ValueConfidence.low;
      case 'O2_ACTIVITY': matched = _stddev(all['o2_b1s1']) > 0 && (_stddev(all['o2_b1s2']) > 0 || all['o2_b1s2'] == null); support = 'تمت مقارنة نشاط O2 المتاح'; title = 'نشاط حساسات O2 يحتاج مراجعة'; confidence = ValueConfidence.low;
      case 'LOAD_HIGH': matched = _averageOr(all['engine_load'], 0) > 75; support = _metric(all['engine_load'], 'حمل المحرك'); title = 'حمل مرتفع أثناء الفحص'; confidence = ValueConfidence.low;
      case 'LOW_SPEED_LOAD': matched = _averageOr(all['engine_load'], 0) > 70 && _averageOr(all['speed'], 999) < 10; support = 'الحمل ${_averageOr(all['engine_load'], double.nan).toStringAsFixed(1)}% والسرعة ${_averageOr(all['speed'], double.nan).toStringAsFixed(1)}'; title = 'حمل مرتفع مع سرعة منخفضة'; confidence = ValueConfidence.low;
      case 'THROTTLE_RESPONSE': matched = _range(all['throttle']) < 2 && _averageOr(all['engine_load'], 0) > 50; support = 'مدى الخانق ${_range(all['throttle']).toStringAsFixed(1)}%'; title = 'استجابة الخانق تحتاج فحصًا'; confidence = ValueConfidence.low;
      case 'RPM_SPEED_MISMATCH': matched = _averageOr(all['rpm'], 0) > 2500 && _averageOr(all['speed'], 0) < 15; support = 'RPM ${_averageOr(all['rpm'], double.nan).toStringAsFixed(0)} والسرعة ${_averageOr(all['speed'], double.nan).toStringAsFixed(0)}'; title = 'عدم تناسب RPM والسرعة'; confidence = ValueConfidence.low;
      case 'MAP_LOAD': matched = _averageOr(all['map'], 0) > 80 && _averageOr(all['engine_load'], 0) > 60; support = 'MAP ${_averageOr(all['map'], double.nan).toStringAsFixed(1)} وLoad ${_averageOr(all['engine_load'], double.nan).toStringAsFixed(1)}'; title = 'حمل مرتفع يحتاج مقارنة بالاستجابة'; confidence = ValueConfidence.low;
      case 'VOLTAGE_LOW': matched = _averageOr(all['battery_voltage'], 99) < 12; support = _metric(all['battery_voltage'], 'جهد البطارية'); title = 'جهد منخفض يحتاج قياسًا مباشرًا';
      case 'VOLTAGE_UNAVAILABLE': matched = all['battery_voltage'] == null; support = 'PID battery_voltage غير مدعوم أو لم يرد'; title = 'بيانات الجهد غير متاحة'; confidence = ValueConfidence.high;
      case 'READINESS': matched = false; support = 'يجب مراجعة readiness من فحص السيارة'; title = 'حالة الجاهزية ليست سببًا مباشرًا'; confidence = ValueConfidence.low;
      case 'SPECIALIZED_REQUIRED': matched = true; support = 'Generic OBD لا يصل إلى وحدة Renault المطلوبة'; title = 'يلزم فحص متخصص للوحدة'; confidence = ValueConfidence.high;
      default: return;
    }
    _rule(evidence, conclusions, id, title, matched, support, confidence);
  }

  void _rule(List<SymptomEvidence> evidence, List<String> conclusions, String id, String title, bool matched, String support, ValueConfidence confidence) {
    evidence.add(SymptomEvidence(title: id, value: matched ? 'ينطبق: $title' : 'لم ينطبق: $title', source: ValueSource.estimated, authority: ValueAuthority.applicationInference, confidence: matched ? confidence : ValueConfidence.unconfirmed, quality: support.contains('غير متاح') || support.contains('لا توجد') ? ValueQuality.missing : ValueQuality.good, ageMs: 0, supportingData: support));
    if (matched) conclusions.add('$title؛ الدليل: $support');
  }

  String _metric(List<num>? values, String name) => values == null || values.isEmpty ? '$name غير متاح' : '$name ${_average(values).toStringAsFixed(1)}';
  double _averageOr(List<num>? values, double fallback) => values == null || values.isEmpty ? fallback : _average(values);
  double _range(List<num>? values) => values == null || values.isEmpty ? 0 : values.reduce((a, b) => a > b ? a : b).toDouble() - values.reduce((a, b) => a < b ? a : b).toDouble();
  double _average(List<num> values) => values.fold<double>(0, (sum, v) => sum + v) / values.length;
  double _stddev(List<num>? values) { if (values == null || values.length < 2) return 0; final avg = _average(values); final variance = values.fold<double>(0, (sum, v) => sum + (v - avg) * (v - avg)) / values.length; return math.sqrt(variance); }
}
