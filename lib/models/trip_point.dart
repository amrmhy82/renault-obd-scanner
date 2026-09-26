class TripPoint {
  final DateTime timestamp;
  final int? rpm;
  final int? speedKmh;
  final int? coolantTempC;

  TripPoint({
    required this.timestamp,
    this.rpm,
    this.speedKmh,
    this.coolantTempC,
  });

  Map<String, dynamic> toJson() => {
        't': timestamp.millisecondsSinceEpoch,
        'r': rpm,
        's': speedKmh,
        'c': coolantTempC,
      };

  factory TripPoint.fromJson(Map<String, dynamic> json) => TripPoint(
        timestamp: DateTime.fromMillisecondsSinceEpoch(json['t'] as int),
        rpm: json['r'] as int?,
        speedKmh: json['s'] as int?,
        coolantTempC: json['c'] as int?,
      );
}
