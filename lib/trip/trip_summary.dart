import 'trip_computer.dart';

class TripSummary {
  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final TripStats stats;

  const TripSummary({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.stats,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': startedAt.millisecondsSinceEpoch,
        'end': endedAt.millisecondsSinceEpoch,
        'distanceKm': stats.distanceKm,
        'avgSpeed': stats.avgSpeedKmh,
        'maxSpeed': stats.maxSpeedKmh,
        'avgRpm': stats.avgRpm,
        'maxRpm': stats.maxRpm,
        'coolantMin': stats.coolantMinC,
        'coolantMax': stats.coolantMaxC,
        'fuel': stats.estimatedFuelLiters,
        'fuelCalibrated': stats.isCalibratedEstimate,
        'durationMs': stats.duration.inMilliseconds,
        'points': stats.pointCount,
      };

  factory TripSummary.fromJson(Map<String, dynamic> j) => TripSummary(
        id: j['id'] as String,
        startedAt: DateTime.fromMillisecondsSinceEpoch(j['start'] as int),
        endedAt: DateTime.fromMillisecondsSinceEpoch(j['end'] as int),
        stats: TripStats(
          pointCount: j['points'] as int? ?? 0,
          duration: Duration(milliseconds: j['durationMs'] as int? ?? 0),
          distanceKm: (j['distanceKm'] as num?)?.toDouble() ?? 0,
          avgSpeedKmh: (j['avgSpeed'] as num?)?.toDouble() ?? 0,
          maxSpeedKmh: (j['maxSpeed'] as num?)?.toInt() ?? 0,
          avgRpm: (j['avgRpm'] as num?)?.toDouble() ?? 0,
          maxRpm: (j['maxRpm'] as num?)?.toInt() ?? 0,
          coolantMinC: (j['coolantMin'] as num?)?.toInt(),
          coolantMaxC: (j['coolantMax'] as num?)?.toInt(),
          estimatedFuelLiters: (j['fuel'] as num?)?.toDouble() ?? 0,
          isCalibratedEstimate: j['fuelCalibrated'] as bool? ?? false,
        ),
      );
}
