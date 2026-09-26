import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../vehicle/mileage_store.dart';
import 'maintenance_item.dart';

/// الفترات (intervalKm) أدناه تقديرات عامة شائعة لمحرك بنزين متوسط الحجم،
/// وليست مأخوذة من دليل مالك رينو فلوانس الرسمي — يُفضّل مراجعته لتأكيد
/// الفترات الدقيقة لسيارتك تحديدًا.
class MaintenanceRepository {
  static const _itemsKey = 'maintenance_items_v1';

  final List<MaintenanceItem> _items = [];
  List<MaintenanceItem> get items => List.unmodifiable(_items);

  int? currentMileage;

  static List<MaintenanceItem> _defaults() => [
        MaintenanceItem(id: 'oil', nameAr: 'زيت المحرك', intervalKm: 10000),
        MaintenanceItem(id: 'oil_filter', nameAr: 'فلتر الزيت', intervalKm: 10000),
        MaintenanceItem(id: 'air_filter', nameAr: 'فلتر الهواء', intervalKm: 20000),
        MaintenanceItem(id: 'cabin_filter', nameAr: 'فلتر المكيف (الكابينة)', intervalKm: 15000),
        MaintenanceItem(id: 'spark_plugs', nameAr: 'البوجيهات', intervalKm: 40000),
        MaintenanceItem(id: 'coolant', nameAr: 'سائل التبريد', intervalKm: 60000),
        MaintenanceItem(id: 'brake_fluid', nameAr: 'زيت الفرامل', intervalKm: 30000),
        MaintenanceItem(id: 'brake_pads', nameAr: 'تيل الفرامل', intervalKm: 30000),
        MaintenanceItem(id: 'battery', nameAr: 'البطارية', intervalKm: 80000),
        MaintenanceItem(id: 'tires', nameAr: 'الإطارات', intervalKm: 40000),
      ];

  Future<void> load() async {
    currentMileage = await MileageStore.get();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_itemsKey);
    _items.clear();
    if (raw == null) {
      _items.addAll(_defaults());
      await _persistItems();
    } else {
      try {
        final list = jsonDecode(raw) as List;
        _items.addAll(list.map((e) => MaintenanceItem.fromJson(e as Map<String, dynamic>)));
      } catch (_) {
        _items.addAll(_defaults());
      }
    }
  }

  Future<void> setCurrentMileage(int km) async {
    currentMileage = km;
    await MileageStore.set(km);
  }

  Future<void> recordService(
    String id, {
    required int atKm,
    DateTime? date,
    double? cost,
    String? workshop,
    String? notes,
  }) async {
    final idx = _items.indexWhere((i) => i.id == id);
    if (idx == -1) return;
    _items[idx].lastServiceKm = atKm;
    _items[idx].lastServiceDate = date ?? DateTime.now();
    if (cost != null) _items[idx].cost = cost;
    if (workshop != null) _items[idx].workshop = workshop;
    if (notes != null) _items[idx].notes = notes;
    await _persistItems();
  }

  Future<void> _persistItems() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_items.map((i) => i.toJson()).toList());
    await prefs.setString(_itemsKey, raw);
  }
}
