class FuelCalibration {
  final double litersAdded;
  final double distanceKm;
  final DateTime recordedAt;

  const FuelCalibration({
    required this.litersAdded,
    required this.distanceKm,
    required this.recordedAt,
  });

  double get consumptionLPer100Km =>
      distanceKm > 0 ? litersAdded / distanceKm * 100 : 0;

  Map<String, dynamic> toJson() => {
        'liters': litersAdded,
        'distance': distanceKm,
        'at': recordedAt.millisecondsSinceEpoch,
      };

  factory FuelCalibration.fromJson(Map<String, dynamic> j) => FuelCalibration(
        litersAdded: (j['liters'] as num).toDouble(),
        distanceKm: (j['distance'] as num).toDouble(),
        recordedAt: DateTime.fromMillisecondsSinceEpoch(j['at'] as int),
      );
}
