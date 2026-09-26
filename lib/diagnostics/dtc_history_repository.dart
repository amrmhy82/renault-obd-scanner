import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dtc_history_entry.dart';

/// يحتفظ بتاريخ كل كود عطل (متى ظهر أول مرة، آخر مرة شوهد، متى مُسح، وكم مرة
/// تكرر ظهوره بعد المسح) — بعكس السكانرات العادية التي تفقد كل الأثر بمجرد
/// الضغط على "مسح". هذا يطبّق مبدأ Read → Analyze → Save → Confirm → Clear
/// → Verify المقترح، بشكل مبسّط وعملي.
class DtcHistoryRepository {
  static const _storageKey = 'dtc_history_v1';

  final Map<String, DtcHistoryEntry> _entries = {};

  List<DtcHistoryEntry> get all => _entries.values.toList()
    ..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return;
    try {
      final list = jsonDecode(raw) as List;
      _entries.clear();
      for (final item in list) {
        final entry = DtcHistoryEntry.fromJson(item as Map<String, dynamic>);
        _entries[entry.code] = entry;
      }
    } catch (_) {
      // بيانات محفوظة تالفة، نتجاهلها ونبدأ سجلًا جديدًا
    }
  }

  /// يُستدعى بعد كل عملية فحص (Scan) لتحديث السجل بالأكواد النشطة حاليًا
  Future<void> recordScan(List<String> currentCodes) async {
    final now = DateTime.now();
    for (final code in currentCodes) {
      final existing = _entries[code];
      if (existing == null) {
        _entries[code] = DtcHistoryEntry(
          code: code,
          firstDetected: now,
          lastSeen: now,
          occurrences: 1,
        );
      } else if (existing.clearedAt != null) {
        // الكود عاد بعد ما كان انمسح سابقًا -> يُحتسب تكرارًا جديدًا
        existing.clearedAt = null;
        existing.lastSeen = now;
        existing.occurrences += 1;
      } else {
        existing.lastSeen = now;
      }
    }
    await _persist();
  }

  /// يُستدعى بعد تنفيذ أمر مسح فعلي ناجح في السيارة (Mode 04)
  Future<void> recordClear() async {
    final now = DateTime.now();
    for (final entry in _entries.values) {
      if (entry.clearedAt == null) {
        entry.clearedAt = now;
      }
    }
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_entries.values.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, raw);
  }
}
