import 'symptom_registry.dart';

class SymptomCoverage {
  static List<Map<String, Object?>> get matrix => SymptomRegistry.all
      .map((s) => {
            'symptom': s.id,
            'dtcReads': const ['03', '07', '0A'],
            'livePids': s.requiredPids,
            'rules': 5,
            'recommendations': s.recommendations.isNotEmpty,
          })
      .toList();
}
