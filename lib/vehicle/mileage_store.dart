import 'package:shared_preferences/shared_preferences.dart';

/// نقطة تخزين واحدة لعداد الكيلومترات الحالي — يستخدمها MaintenanceRepository
/// وVehicleProfileScreen معًا، حتى لا يظهر رقمان مختلفان للعداد في شاشتين.
class MileageStore {
  static const _key = 'vehicle_current_mileage_v1';

  static Future<int?> get() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_key);
  }

  static Future<void> set(int km) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, km);
  }
}
