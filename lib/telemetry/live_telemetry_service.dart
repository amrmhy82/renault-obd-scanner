import 'dart:async';
import '../core/elm327_session.dart';
import '../core/pid_registry.dart';
import 'data_quality.dart';
import 'vehicle_state.dart';

/// مُجدوِل حقيقي بمواعيد استحقاق (deadlines) مستقلة لكل PID، بدل عدّاد
/// دورات ثابت (% 3 و% 12 في النسخة السابقة). كل PID له موعد استحقاق خاص
/// (nextDueAt) يُحسب من زمن انتهاء آخر قراءة فعلية + الفاصل الزمني لفئته،
/// وليس من عدد "دورات Timer" وهمية. بما أن الاتصال تسلسلي (قراءة واحدة
/// بالمرة)، الحلقة تختار في كل مرة أقرب PID مستحق وتنفذه، ثم تعيد الجدولة.
class LiveTelemetryService {
  final Elm327Session session;
  LiveTelemetryService(this.session);

  static const Map<PollClass, Duration> _intervals = {
    PollClass.fast: Duration(milliseconds: 700),
    PollClass.medium: Duration(milliseconds: 2500),
    PollClass.slow: Duration(milliseconds: 10000),
  };

  final StreamController<VehicleState> _controller =
      StreamController<VehicleState>.broadcast();
  Stream<VehicleState> get stream => _controller.stream;

  final Map<String, DateTime> _nextDueAt = {};
  final Map<String, num> _values = {};
  final Map<String, DateTime> _lastUpdated = {};
  final Map<String, double> _ratesHz = {};
  bool _running = false;
  bool _stopRequested = false;

  void start() {
    if (_running) return;
    _stopRequested = false;
    _running = true;
    final now = DateTime.now();
    _nextDueAt.clear();
    for (final pid in PidRegistry.all) {
      _nextDueAt[pid.key] = now; // الكل مستحق فورًا عند بدء الاتصال
    }
    _loop();
  }

  void stop() {
    _stopRequested = true;
  }

  Future<void> _loop() async {
    while (!_stopRequested) {
      if (!session.isConnected) {
        _publish();
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }

      final now = DateTime.now();
      PidDefinition? duePid;
      for (final pid in PidRegistry.all) {
        if (session.isPidSupported(pid.pidNumber) == false) {
          _nextDueAt[pid.key] = now.add(_intervals[pid.pollClass]!);
          continue;
        }
        final due = _nextDueAt[pid.key] ?? now;
        if (!due.isAfter(now)) {
          duePid = pid;
          break;
        }
      }

      if (duePid == null) {
        // لا شيء مستحق الآن فعليًا؛ ننام فقط لأقصر مدة متبقية حتى أقرب موعد
        final soonest = _nextDueAt.values.isEmpty
            ? now.add(const Duration(milliseconds: 200))
            : _nextDueAt.values.reduce((a, b) => a.isBefore(b) ? a : b);
        final wait = soonest.difference(DateTime.now());
        await Future.delayed(wait.isNegative ? const Duration(milliseconds: 30) : wait);
        continue;
      }

      try {
        final value = await session.readPid(duePid);
        if (value != null) {
          final receivedAt = DateTime.now();
          final previous = _lastUpdated[duePid.key];
          if (previous != null) {
            final elapsedMs = receivedAt.difference(previous).inMilliseconds;
            if (elapsedMs > 0) _ratesHz[duePid.key] = 1000 / elapsedMs;
          }
          _values[duePid.key] = value;
          _lastUpdated[duePid.key] = receivedAt;
        }
      } catch (_) {
        // تجاهل خطأ قراءة PID واحد ومتابعة الباقي بدل إيقاف الحلقة كلها
      }
      // موعد الاستحقاق التالي يُحسب من زمن *انتهاء* القراءة الفعلية، وليس
      // من بداية الدورة — فيعكس فعليًا زمن الاستجابة الحقيقي للسيارة.
      _nextDueAt[duePid.key] = DateTime.now().add(_intervals[duePid.pollClass]!);
      _publish();
    }
    _running = false;
  }

  void _publish() {
    if (_controller.isClosed) return;
    final now = DateTime.now();
    final fields = <String, TelemetryField>{};
    for (final pid in PidRegistry.all) {
      final updated = _lastUpdated[pid.key];
      final value = _values[pid.key];
      final age = updated == null ? null : now.difference(updated);
      final staleAfter = _stalenessThreshold(pid.pollClass);
      fields[pid.key] = TelemetryField(
        value: value,
        source: ValueSource.genericObd,
        authority: ValueAuthority.ecuResponse,
        confidence: value == null ? ValueConfidence.unconfirmed : ValueConfidence.high,
        quality: value == null
            ? ValueQuality.missing
            : age != null && age > staleAfter
                ? ValueQuality.stale
                : ValueQuality.good,
        timestamp: updated,
        rateHz: _ratesHz[pid.key],
      );
    }
    _controller.add(VehicleState(
      values: Map.of(_values),
      fields: fields,
      connected: session.isConnected,
      lastUpdate: now,
    ));
  }

  Duration _stalenessThreshold(PollClass pollClass) {
    switch (pollClass) {
      case PollClass.fast:
        return const Duration(seconds: 2);
      case PollClass.medium:
        return const Duration(seconds: 6);
      case PollClass.slow:
        return const Duration(seconds: 25);
    }
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
