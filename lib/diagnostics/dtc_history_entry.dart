class DtcHistoryEntry {
  final String code;
  final DateTime firstDetected;
  DateTime lastSeen;
  DateTime? clearedAt;
  int occurrences;

  DtcHistoryEntry({
    required this.code,
    required this.firstDetected,
    required this.lastSeen,
    this.clearedAt,
    this.occurrences = 1,
  });

  bool get isActive => clearedAt == null;

  Map<String, dynamic> toJson() => {
        'code': code,
        'first': firstDetected.millisecondsSinceEpoch,
        'last': lastSeen.millisecondsSinceEpoch,
        'cleared': clearedAt?.millisecondsSinceEpoch,
        'occ': occurrences,
      };

  factory DtcHistoryEntry.fromJson(Map<String, dynamic> j) => DtcHistoryEntry(
        code: j['code'] as String,
        firstDetected: DateTime.fromMillisecondsSinceEpoch(j['first'] as int),
        lastSeen: DateTime.fromMillisecondsSinceEpoch(j['last'] as int),
        clearedAt: j['cleared'] != null
            ? DateTime.fromMillisecondsSinceEpoch(j['cleared'] as int)
            : null,
        occurrences: j['occ'] as int? ?? 1,
      );
}
