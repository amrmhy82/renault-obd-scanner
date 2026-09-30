enum ValueSource { genericObd, renaultDefinition, estimated }

enum ValueAuthority { ecuResponse, applicationInference, uncertain }

enum ValueConfidence { high, medium, low, unconfirmed }

enum ValueQuality { good, degraded, stale, invalid, missing }

extension ValueQualityLabels on ValueQuality {
  String get labelAr {
    switch (this) {
      case ValueQuality.good:
        return 'جيدة';
      case ValueQuality.degraded:
        return 'متدهورة';
      case ValueQuality.stale:
        return 'قديمة';
      case ValueQuality.invalid:
        return 'غير صالحة';
      case ValueQuality.missing:
        return 'غير متاحة';
    }
  }
}

extension ValueAuthorityLabels on ValueAuthority {
  String get labelAr => switch (this) {
        ValueAuthority.ecuResponse => 'رد ECU',
        ValueAuthority.applicationInference => 'استنتاج التطبيق',
        ValueAuthority.uncertain => 'غير مؤكدة',
      };
}

class TelemetryField {
  final num? value;
  final ValueSource source;
  final ValueAuthority authority;
  final ValueConfidence confidence;
  final ValueQuality quality;
  final DateTime? timestamp;
  final double? rateHz;

  const TelemetryField({
    required this.value,
    required this.source,
    required this.authority,
    required this.confidence,
    required this.quality,
    this.timestamp,
    this.rateHz,
  });

  int? ageMs(DateTime now) => timestamp == null
      ? null
      : now.difference(timestamp!).inMilliseconds.clamp(0, 0x7fffffff).toInt();
}
