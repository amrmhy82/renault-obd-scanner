/// حالة موحدة للسيارة في لحظة معينة — كل الشاشات (Dashboard، Trip Log لاحقًا،
/// Health Score مستقبلًا) تقرأ من هذا الكائن فقط، بدل كل شاشة تستقصي PIDs
/// بنفسها كما كان في النسخة السابقة.
class VehicleState {
  final Map<String, num> values;
  final bool connected;
  final DateTime lastUpdate;

  const VehicleState({
    this.values = const {},
    this.connected = false,
    required this.lastUpdate,
  });

  num? operator [](String key) => values[key];

  factory VehicleState.initial() =>
      VehicleState(lastUpdate: DateTime.now(), connected: false);
}
