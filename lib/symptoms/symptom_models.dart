import '../telemetry/data_quality.dart';

enum SymptomCategory { engine, fuel, cooling, electrical, transmission, general }
enum SymptomSeverity { low, medium, high }
enum OperatingState { idle, cruise, load, decel, unknown }

class SymptomDefinition {
  final String id;
  final String nameAr;
  final String descriptionAr;
  final SymptomCategory category;
  final SymptomSeverity severity;
  final List<String> relatedDtcs;
  final List<String> requiredPids;
  final List<String> recommendations;
  final int idleSeconds;
  final int loadSeconds;

  const SymptomDefinition({
    required this.id,
    required this.nameAr,
    required this.descriptionAr,
    required this.category,
    required this.severity,
    this.relatedDtcs = const [],
    this.requiredPids = const [],
    this.recommendations = const [],
    this.idleSeconds = 10,
    this.loadSeconds = 0,
  });
}

class SymptomEvidence {
  final String title;
  final String value;
  final ValueSource source;
  final ValueAuthority authority;
  final ValueConfidence confidence;
  final String supportingData;
  final ValueQuality quality;
  final DateTime timestamp;
  final int? ageMs;
  final double? rateHz;
  final OperatingState state;

  SymptomEvidence({
    required this.title,
    required this.value,
    required this.source,
    required this.authority,
    required this.confidence,
    this.supportingData = '',
    this.quality = ValueQuality.good,
    DateTime? timestamp,
    this.ageMs,
    this.rateHz,
    this.state = OperatingState.unknown,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, Object?> toJson() => {
        'title': title,
        'value': value,
        'source': source.name,
        'authority': authority.name,
        'confidence': confidence.name,
        'supportingData': supportingData,
        'quality': quality.name,
        'timestamp': timestamp.toIso8601String(),
        'ageMs': ageMs,
        'rateHz': rateHz,
        'operatingState': state.name,
      };
}

class SymptomReport {
  final SymptomDefinition symptom;
  final DateTime timestamp;
  final List<SymptomEvidence> evidence;
  final List<String> conclusions;
  final List<String> uncertainties;
  final List<Map<String, Object?>> coverage;

  const SymptomReport({
    required this.symptom,
    required this.timestamp,
    required this.evidence,
    required this.conclusions,
    required this.uncertainties,
    this.coverage = const [],
  });

  Map<String, Object?> toJson() => {
        'symptomId': symptom.id,
        'symptom': symptom.nameAr,
        'timestamp': timestamp.toIso8601String(),
        'evidence': evidence.map((e) => e.toJson()).toList(),
        'conclusions': conclusions,
        'uncertainties': uncertainties,
        'coverage': coverage,
      };
}
