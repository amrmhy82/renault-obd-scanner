import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'trip_summary.dart';

/// يحفظ ملخصات الرحلات فقط (وليس كل نقطة خام) حتى يبقى حجم التخزين صغيرًا.
class TripSummaryRepository {
  static const _storageKey = 'trip_summaries_v1';
  static const _maxTrips = 200;

  final List<TripSummary> _trips = [];

  /// الأحدث أولًا
  List<TripSummary> get trips => List.unmodifiable(_trips.reversed);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      _trips
        ..clear()
        ..addAll(list.map((e) => TripSummary.fromJson(e as Map<String, dynamic>)));
    } catch (_) {
      // تجاهل بيانات تالفة
    }
  }

  Future<void> addTrip(TripSummary trip) async {
    _trips.add(trip);
    if (_trips.length > _maxTrips) _trips.removeAt(0);
    await _persist();
  }

  Future<void> clear() async {
    _trips.clear();
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_trips.map((t) => t.toJson()).toList());
    await prefs.setString(_storageKey, raw);
  }
}
