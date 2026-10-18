import 'symptom_registry.dart';

class SymptomCoverage {
  static List<Map<String, Object?>> get matrix => SymptomRegistry.all
      .map((s) => {
            'symptom': s.id,
            'dtcReads': const ['03', '07', '0A'],
            'livePids': s.requiredPids,
            'rules': s.ruleIds.length,
            'ruleIds': s.ruleIds,
            'recommendations': s.recommendations.isNotEmpty,
          })
      .toList();
}
