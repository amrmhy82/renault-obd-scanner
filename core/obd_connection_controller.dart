import 'dart:async';
import 'package:flutter/foundation.dart';
import '../diagnostics/dtc_history_repository.dart';
import '../models/trip_point.dart';
import '../services/trip_log_service.dart';
import '../telemetry/live_telemetry_service.dart';
import '../telemetry/vehicle_state.dart';
import '../trip/fuel_calibration_repository.dart';
import '../trip/trip_computer.dart';
import '../trip/trip_summary.dart';
import '../trip/trip_summary_repository.dart';
import 'elm327_session.dart';
import 'elm_session_state.dart';

/// المالك الوحيد لجلسة ELM327 والخدمات المرتبطة بها (التلِمتري، سجل الرحلة،
/// ملخصات الرحلات، سجل الأعطال). الشاشات لا تملك الاتصال ولا تقطعه عند
/// إغلاقها — تقرأ من هذا المتحكم فقط. الاتصال يستمر طالما لم يُستدعَ
/// [disconnect] أو يُستبدل بجلسة جديدة عبر [attachSession].
class ObdConnectionController extends ChangeNotifier {
  final TripLogService tripLogService = TripLogService();
  final DtcHistoryRepository dtcHistoryRepository = DtcHistoryRepository();
  final TripSummaryRepository tripSummaryRepository = TripSummaryRepository();
  final FuelCalibrationRepository _fuelCalibrationRepository =
      FuelCalibrationRepository();

  Elm327Session? _session;
  LiveTelemetryService? _telemetry;
  StreamSubscription<VehicleState>? _telemetrySub;
  StreamSubscription<ElmSessionState>? _stateSub;

  String? _deviceLabel;
  bool _isConnecting = false;
  bool _reposLoaded = false;

  final List<TripPoint> _currentTripPoints = [];
  DateTime _tripStartedAt = DateTime.now();

  Elm327Session? get session => _session;
  LiveTelemetryService? get telemetryService => _telemetry;
  String? get deviceLabel => _deviceLabel;
  bool get isConnecting => _isConnecting;
  bool get isConnected => _session != null && _session!.isConnected;

  /// نقاط الرحلة الحالية (تُجمَّع طالما الاتصال قائم، بغضّ النظر عن الشاشة
  /// المفتوحة).
  List<TripPoint> get currentTripPoints => _currentTripPoints;

  /// يحمّل المستودعات مرة واحدة فقط (آمن للاستدعاء المتكرر).
  Future<void> loadReposIfNeeded() async {
    if (_reposLoaded) return;
    _reposLoaded = true;
    await Future.wait([
      tripLogService.load(),
      tripSummaryRepository.load(),
      dtcHistoryRepository.load(),
      _fuelCalibrationRepository.load(),
    ]);
  }

  void setConnecting(bool value) {
    if (_isConnecting == value) return;
    _isConnecting = value;
    notifyListeners();
  }

  /// يربط جلسة مهيّأة وجاهزة (بعد نجاح transport.connect + initialize).
  /// أي جلسة سابقة تُقطع وتُحفظ رحلتها أولًا.
  Future<void> attachSession({
    required Elm327Session session,
    required String deviceLabel,
  }) async {
    await _teardown();
    await loadReposIfNeeded();

    _session = session;
    _deviceLabel = deviceLabel;
    _isConnecting = false;
    _tripStartedAt = DateTime.now();
    _currentTripPoints.clear();

    final telemetry = LiveTelemetryService(session);
    _telemetry = telemetry;
    _telemetrySub = telemetry.stream.listen(_onVehicleState);
    _stateSub = session.stateStream.listen((_) => notifyListeners());
    telemetry.start();

    notifyListeners();
  }

  void _onVehicleState(VehicleState state) {
    final point = TripPoint(
      timestamp: state.lastUpdate,
      rpm: state['rpm']?.round(),
      speedKmh: state['speed']?.round(),
      coolantTempC: state['coolant_temp']?.round(),
    );
    tripLogService.addPoint(point);
    _currentTripPoints.add(point);
  }

  /// قطع يدوي من المستخدم.
  Future<void> disconnect() async {
    await _teardown();
    notifyListeners();
  }

  Future<void> _teardown() async {
    final session = _session;
    final telemetry = _telemetry;
    await _telemetrySub?.cancel();
    await _stateSub?.cancel();
    _telemetrySub = null;
    _stateSub = null;
    _session = null;
    _telemetry = null;
    _deviceLabel = null;

    telemetry?.dispose();
    if (session != null) {
      try {
        await session.transport.disconnect();
      } catch (_) {
        // الاتصال منقطع أصلًا — نتجاهل
      }
      session.dispose();
    }

    await tripLogService.flush();
    await _saveTripSummaryIfNeeded();
    _currentTripPoints.clear();
  }

  Future<void> _saveTripSummaryIfNeeded() async {
    if (_currentTripPoints.length < 2) return;
    final stats = TripComputer.compute(
      List<TripPoint>.of(_currentTripPoints),
      fuelConsumptionLPer100Km: _fuelCalibrationRepository.currentRateLPer100Km,
      isCalibratedRate: _fuelCalibrationRepository.isCalibrated,
    );
    if (stats.pointCount < 2) return;
    await tripSummaryRepository.addTrip(TripSummary(
      id: _tripStartedAt.millisecondsSinceEpoch.toString(),
      startedAt: _tripStartedAt,
      endedAt: DateTime.now(),
      stats: stats,
    ));
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }
}
