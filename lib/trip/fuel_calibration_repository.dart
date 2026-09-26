import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'fuel_calibration.dart';
import 'trip_computer.dart' show kAssumedFuelConsumptionLPer100Km;

/// بدل الاعتماد الدائم على رقم استهلاك افتراضي عام (7.5 لتر/100كم)، يسمح
/// هذا المستودع للمستخدم بإدخال كمية وقود فعلية + مسافة فعلية عند كل
/// تعبئة، فيبني التطبيق تدريجيًا معدل استهلاك حقيقي خاصًا بسيارته.
class FuelCalibrationRepository {
  static const _key = 'fuel_calibrations_v1';
  static const _maxEntries = 20;

  final List<FuelCalibration> _entries = [];

  /// الأحدث أولًا
  List<FuelCalibration> get entries => List.unmodifiable(_entries.reversed);

  bool get isCalibrated => _entries.isNotEmpty;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      _entries
        ..clear()
        ..addAll(list.map((e) => FuelCalibration.fromJson(e as Map<String, dynamic>)));
    } catch (_) {
      // تجاهل بيانات تالفة
    }
  }

  Future<void> addEntry(FuelCalibration entry) async {
    _entries.add(entry);
    if (_entries.length > _maxEntries) _entries.removeAt(0);
    await _persist();
  }

  Future<void> clear() async {
    _entries.clear();
    await _persist();
  }

  /// المعدل المُعتمد حاليًا: متوسط آخر 3 تعبئات إن وُجدت، وإلا الرقم
  /// الافتراضي العام. يصبح أدق كلما أضاف المستخدم قياسات أكثر.
  double get currentRateLPer100Km {
    if (_entries.isEmpty) return kAssumedFuelConsumptionLPer100Km;
    final recent = _entries.length > 3 ? _entries.sublist(_entries.length - 3) : _entries;
    final sum = recent.map((e) => e.consumptionLPer100Km).reduce((a, b) => a + b);
    return sum / recent.length;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await prefs.setString(_key, raw);
  }
}
