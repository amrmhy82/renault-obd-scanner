import '../models/trip_point.dart';

/// متوسط استهلاك تقريبي (لتر/100كم) لمحرك 1.6 بنزين شبيه برينو فلوانس 2017.
/// هذا رقم افتراضي فقط للتقدير التقريبي جدًا — **ليس قراءة فعلية** من حساس
/// تدفق وقود (MAF)، لأن هذا غير مُجمَّع حاليًا. عدّله إن عرفت استهلاك سيارتك
/// الفعلي من محطة الوقود.
const double kAssumedFuelConsumptionLPer100Km = 7.5;

class TripStats {
  final int pointCount;
  final Duration duration;
  final double distanceKm;
  final double avgSpeedKmh;
  final int maxSpeedKmh;
  final double avgRpm;
  final int maxRpm;
  final int? coolantMinC;
  final int? coolantMaxC;
  final double estimatedFuelLiters;
  final bool isCalibratedEstimate;

  const TripStats({
    required this.pointCount,
    required this.duration,
    required this.distanceKm,
    required this.avgSpeedKmh,
    required this.maxSpeedKmh,
    required this.avgRpm,
    required this.maxRpm,
    required this.coolantMinC,
    required this.coolantMaxC,
    required this.estimatedFuelLiters,
    required this.isCalibratedEstimate,
  });

  static const empty = TripStats(
    pointCount: 0,
    duration: Duration.zero,
    distanceKm: 0,
    avgSpeedKmh: 0,
    maxSpeedKmh: 0,
    avgRpm: 0,
    maxRpm: 0,
    coolantMinC: null,
    coolantMaxC: null,
    estimatedFuelLiters: 0,
    isCalibratedEstimate: false,
  );
}

/// يحسب إحصائيات رحلة من قائمة نقاط مسجّلة (لا يقرأ أي شيء من ELM327 مباشرة).
/// المسافة تُقدَّر بتكامل السرعة عبر الزمن بين كل نقطتين متتاليتين
/// (طريقة شبه المنحرف / Trapezoidal)، وهذا تقدير معقول لكنه ليس بدقة عداد
/// GPS حقيقي.
class TripComputer {
  static TripStats compute(
    List<TripPoint> points, {
    double fuelConsumptionLPer100Km = kAssumedFuelConsumptionLPer100Km,
    bool isCalibratedRate = false,
  }) {
    if (points.length < 2) return TripStats.empty;

    final sorted = [...points]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final duration = sorted.last.timestamp.difference(sorted.first.timestamp);

    double distanceKm = 0;
    for (int i = 1; i < sorted.length; i++) {
      final a = sorted[i - 1];
      final b = sorted[i];
      final dtHours = b.timestamp.difference(a.timestamp).inMilliseconds / 3600000.0;
      final s1 = a.speedKmh ?? 0;
      final s2 = b.speedKmh ?? 0;
      distanceKm += ((s1 + s2) / 2) * dtHours;
    }

    final speeds = sorted.map((p) => p.speedKmh).whereType<int>().toList();
    final rpms = sorted.map((p) => p.rpm).whereType<int>().toList();
    final coolants = sorted.map((p) => p.coolantTempC).whereType<int>().toList();

    final maxSpeed = speeds.isEmpty ? 0 : speeds.reduce((a, b) => a > b ? a : b);
    final maxRpm = rpms.isEmpty ? 0 : rpms.reduce((a, b) => a > b ? a : b);
    final avgRpm = rpms.isEmpty ? 0.0 : rpms.reduce((a, b) => a + b) / rpms.length;
    final durationHours = duration.inMilliseconds / 3600000.0;
    final avgSpeed = durationHours > 0 ? distanceKm / durationHours : 0.0;
    final estimatedFuel = distanceKm / 100 * fuelConsumptionLPer100Km;

    return TripStats(
      pointCount: sorted.length,
      duration: duration,
      distanceKm: distanceKm,
      avgSpeedKmh: avgSpeed,
      maxSpeedKmh: maxSpeed,
      avgRpm: avgRpm,
      maxRpm: maxRpm,
      coolantMinC: coolants.isEmpty ? null : coolants.reduce((a, b) => a < b ? a : b),
      coolantMaxC: coolants.isEmpty ? null : coolants.reduce((a, b) => a > b ? a : b),
      estimatedFuelLiters: estimatedFuel,
      isCalibratedEstimate: isCalibratedRate,
    );
  }
}
