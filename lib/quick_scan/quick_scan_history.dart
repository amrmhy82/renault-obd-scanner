import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'quick_scan_service.dart';

class QuickScanHistory {
  static const _reportKey = 'last_quick_scan_report_v1';

  Future<void> save(QuickScanReport report) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_reportKey, jsonEncode(report.toJson()));
  }

  Future<Map<String, dynamic>?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_reportKey);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
