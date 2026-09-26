import '../core/pid_registry.dart';
import '../telemetry/vehicle_state.dart';
import 'health_finding.dart';
import 'health_rule.dart';

class HealthReport {
  final int score;
  final List<HealthFinding> findings;
  final int confidencePercent;
  final List<String> availableIndicatorsAr;
  final List<String> missingIndicatorsAr;

  const HealthReport({
    required this.score,
    required this.findings,
    required this.confidencePercent,
    required this.availableIndicatorsAr,
    required this.missingIndicatorsAr,
  });
}

/// محرك قواعد صريح (Rules Engine) — عمدًا بدون أي ذكاء اصطناعي أو نموذج
/// تعلّم آلي، لأن ذلك يحتاج بيانات تاريخية حقيقية من قيادتك غير متوفرة بعد.
/// كل قاعدة أدناه بيانات صريحة يسهل تعديلها أو إضافة أخرى بجانبها.
class HealthScoreEngine {
  static final List<HealthRule> rules = [
    HealthRule(
      id: 'dtc_active',
      title: 'أكواد أعطال نشطة',
      severity: HealthSeverity.warning,
      scoreImpact: -10,
      condition: (state, dtcs) => dtcs.isNotEmpty,
      explanation: (state, dtcs) =>
          'يوجد ${dtcs.length} كود عطل نشط حاليًا: ${dtcs.join('، ')}.',
      recommendation: 'راجع تفاصيل كل كود في شاشة الأعطال، وتوجّه لفني إذا استمر ظهوره بعد المسح.',
    ),
    HealthRule(
      id: 'coolant_overheat',
      title: 'ارتفاع خطير في حرارة سائل التبريد',
      severity: HealthSeverity.critical,
      scoreImpact: -25,
      condition: (state, dtcs) => (state['coolant_temp'] ?? 0) >= 108,
      explanation: (state, dtcs) =>
          'حرارة سائل التبريد ${state['coolant_temp']}° وهي أعلى من الحد الآمن التقريبي (108°).',
      recommendation: 'أوقف السيارة بأمان فورًا وتحقق من مستوى سائل التبريد. القيادة المستمرة بهذه الحرارة قد تضر المحرك بشكل دائم.',
    ),
    HealthRule(
      id: 'coolant_high',
      title: 'حرارة سائل التبريد أعلى من المعتاد',
      severity: HealthSeverity.warning,
      scoreImpact: -10,
      condition: (state, dtcs) {
        final t = state['coolant_temp'];
        return t != null && t >= 100 && t < 108;
      },
      explanation: (state, dtcs) =>
          'حرارة سائل التبريد ${state['coolant_temp']}°، أعلى من المعدل الطبيعي التقريبي (~85–95°).',
      recommendation: 'راقب المؤشر أثناء القيادة؛ إذا استمر بالارتفاع توقف وتحقق من مستوى السائل والمروحة.',
    ),
    HealthRule(
      id: 'charging_issue',
      title: 'مشكلة محتملة في نظام الشحن',
      severity: HealthSeverity.warning,
      scoreImpact: -20,
      condition: (state, dtcs) {
        final v = state['battery_voltage'];
        final rpm = state['rpm'];
        return v != null && rpm != null && rpm > 500 && v < 13.2;
      },
      explanation: (state, dtcs) =>
          'جهد نظام الكهرباء ${state['battery_voltage']?.toStringAsFixed(2)} فولت أثناء دوران المحرك، وهو أقل من نطاق الشحن الطبيعي التقريبي (13.5–14.5 فولت).',
      recommendation: 'تحقق من المولّد (الدينمو) وسيور المحرك وتوصيلات البطارية عند فرصة قريبة.',
    ),
    HealthRule(
      id: 'battery_weak',
      title: 'جهد بطارية منخفض',
      severity: HealthSeverity.warning,
      scoreImpact: -15,
      condition: (state, dtcs) {
        final v = state['battery_voltage'];
        return v != null && v < 11.8;
      },
      explanation: (state, dtcs) =>
          'جهد البطارية ${state['battery_voltage']?.toStringAsFixed(2)} فولت، وهو منخفض عن الطبيعي.',
      recommendation: 'قد تحتاج البطارية شحنًا أو فحصًا أو استبدالًا إذا تكرر هذا مع تشغيل المحرك.',
    ),
  ];

  static HealthReport evaluate(
    VehicleState state,
    List<String> activeDtcCodes, {
    required bool dtcScanned,
  }) {
    int score = 100;
    final findings = <HealthFinding>[];
    for (final rule in rules) {
      if (rule.condition(state, activeDtcCodes)) {
        score += rule.scoreImpact;
        findings.add(HealthFinding(
          title: rule.title,
          explanation: rule.explanation(state, activeDtcCodes),
          recommendation: rule.recommendation,
          severity: rule.severity,
          scoreImpact: rule.scoreImpact,
        ));
      }
    }
    if (score < 0) score = 0;
    if (score > 100) score = 100;

    // مستوى الثقة: نسبة المؤشرات المتاحة فعليًا من إجمالي المؤشرات المتتبَّعة
    // (كل PIDs المسجّلة + فحص DTC). هذا يمنع عرض تقييم "ممتاز" واثق بناءً
    // على بيانات جزئية فقط (مثلًا لحظة الاتصال الأولى قبل وصول أي قراءة).
    final available = <String>[];
    final missing = <String>[];
    for (final pid in PidRegistry.all) {
      if (state[pid.key] != null) {
        available.add(pid.nameAr);
      } else {
        missing.add(pid.nameAr);
      }
    }
    if (dtcScanned) {
      available.add('فحص أكواد الأعطال');
    } else {
      missing.add('فحص أكواد الأعطال');
    }
    final totalIndicators = PidRegistry.all.length + 1;
    final confidence = ((available.length / totalIndicators) * 100).round();

    return HealthReport(
      score: score,
      findings: findings,
      confidencePercent: confidence,
      availableIndicatorsAr: available,
      missingIndicatorsAr: missing,
    );
  }
}
