enum HealthSeverity { info, warning, critical }

class HealthFinding {
  final String title;
  final String explanation;
  final String recommendation;
  final HealthSeverity severity;
  final int scoreImpact; // قيمة سالبة

  const HealthFinding({
    required this.title,
    required this.explanation,
    required this.recommendation,
    required this.severity,
    required this.scoreImpact,
  });
}
