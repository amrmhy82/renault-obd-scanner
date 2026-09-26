import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'vehicle_profile.dart';

class VehicleProfileRepository {
  static const _key = 'vehicle_profile_v1';

  VehicleProfile profile = VehicleProfile();

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return;
    try {
      profile = VehicleProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      profile = VehicleProfile();
    }
  }

  Future<void> save(VehicleProfile updated) async {
    profile = updated;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(updated.toJson()));
  }
}
