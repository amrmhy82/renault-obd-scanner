class MaintenanceItem {
  final String id;
  final String nameAr;
  final int intervalKm;
  int? lastServiceKm;
  DateTime? lastServiceDate;
  double? cost;
  String? workshop;
  String? notes;

  MaintenanceItem({
    required this.id,
    required this.nameAr,
    required this.intervalKm,
    this.lastServiceKm,
    this.lastServiceDate,
    this.cost,
    this.workshop,
    this.notes,
  });

  /// الكيلومترات المتبقية حتى موعد الصيانة القادم، أو null إن لم تتوفر بيانات كافية
  int? remainingKm(int? currentMileage) {
    if (lastServiceKm == null || currentMileage == null) return null;
    final due = lastServiceKm! + intervalKm;
    return due - currentMileage;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': nameAr,
        'interval': intervalKm,
        'lastKm': lastServiceKm,
        'lastDate': lastServiceDate?.millisecondsSinceEpoch,
        'cost': cost,
        'workshop': workshop,
        'notes': notes,
      };

  factory MaintenanceItem.fromJson(Map<String, dynamic> j) => MaintenanceItem(
        id: j['id'] as String,
        nameAr: j['name'] as String,
        intervalKm: j['interval'] as int,
        lastServiceKm: j['lastKm'] as int?,
        lastServiceDate: j['lastDate'] != null
            ? DateTime.fromMillisecondsSinceEpoch(j['lastDate'] as int)
            : null,
        cost: (j['cost'] as num?)?.toDouble(),
        workshop: j['workshop'] as String?,
        notes: j['notes'] as String?,
      );
}
