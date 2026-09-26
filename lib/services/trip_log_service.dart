import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/trip_point.dart';

/// يسجل قراءات الرحلة (RPM/السرعة/الحرارة) عبر الزمن ويحفظها محليًا.
///
/// التخزين دفعي (Batch) عمدًا: لا نكتب SharedPreferences مع كل نقطة (كان هذا
/// يعني إعادة تسلسل وكتابة JSON السجل الكامل كل ~700ms)، بل نجمع النقاط في
/// الذاكرة ونكتب دفعة واحدة كل [_batchIntervalSeconds] ثانية أو كل
/// [_batchCountThreshold] نقطة جديدة — أيهما أسبق. عند إنهاء الرحلة
/// (flushAndClose) نكتب أي بيانات متبقية فورًا حتى لا نخسر آخر دفعة.
class TripLogService {
  static const _storageKey = 'trip_log_points_v1';
  static const _maxPoints = 3600;
  static const _batchIntervalSeconds = 20;
  static const _batchCountThreshold = 15;

  final List<TripPoint> _points = [];
  List<TripPoint> get points => List.unmodifiable(_points);

  int _pendingUnpersisted = 0;
  Timer? _flushTimer;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        _points
          ..clear()
          ..addAll(
            list.map((e) => TripPoint.fromJson(e as Map<String, dynamic>)),
          );
      } catch (_) {
        // بيانات محفوظة تالفة، نتجاهلها ونبدأ سجل جديد
      }
    }
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(
      const Duration(seconds: _batchIntervalSeconds),
      (_) => _flushIfNeeded(),
    );
  }

  Future<void> addPoint(TripPoint point) async {
    _points.add(point);
    if (_points.length > _maxPoints) {
      _points.removeAt(0);
    }
    _pendingUnpersisted++;
    if (_pendingUnpersisted >= _batchCountThreshold) {
      await flush();
    }
  }

  Future<void> _flushIfNeeded() async {
    if (_pendingUnpersisted > 0) await flush();
  }

  /// كتابة فورية لأي بيانات مُجمَّعة لم تُحفظ بعد
  Future<void> flush() async {
    if (_pendingUnpersisted == 0) return;
    await _persist();
    _pendingUnpersisted = 0;
  }

  Future<void> clear() async {
    _points.clear();
    _pendingUnpersisted = 0;
    await _persist();
  }

  /// يُستدعى عند إغلاق الشاشة/انتهاء الرحلة: يوقف مؤقت الدفعات ويضمن كتابة
  /// آخر البيانات المتبقية فورًا بدل انتظار الدورة التالية.
  Future<void> flushAndClose() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await flush();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_points.map((p) => p.toJson()).toList());
    await prefs.setString(_storageKey, raw);
  }
}
