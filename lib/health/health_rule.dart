import '../telemetry/vehicle_state.dart';
import 'health_finding.dart';

/// قاعدة واحدة معبّرة كبيانات صريحة (شرط + أثر على النقاط + شرح + توصية)
/// بدل أي منطق ذكاء اصطناعي أو تعلّم آلي. هذا يجعل النظام قابلًا للمراجعة
/// والتعديل بسهولة: كل قاعدة تُقرأ وتُفهم بمعزل عن البقية.
class HealthRule {
  final String id;
  final String title;
  final HealthSeverity severity;
  final int scoreImpact; // قيمة سالبة
  final bool Function(VehicleState state, List<String> activeDtcCodes) condition;
  final String Function(VehicleState state, List<String> activeDtcCodes) explanation;
  final String recommendation;

  const HealthRule({
    required this.id,
    required this.title,
    required this.severity,
    required this.scoreImpact,
    required this.condition,
    required this.explanation,
    required this.recommendation,
  });
}
