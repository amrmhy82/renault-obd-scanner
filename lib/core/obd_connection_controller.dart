import 'dart:async';
import 'package:flutter/foundation.dart';
import '../diagnostics/dtc_history_repository.dart';
import '../data/data_logger_service.dart';
import '../reports/report_archive_service.dart';
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

/// Owns the active ELM327 session and the services that depend on it.
/// Screens observe this controller instead of owning or disposing transports.
class ObdConnectionController extends ChangeNotifier {
  final TripLogService tripLogService = TripLogService();
  final DtcHistoryRepository dtcHistoryRepository = DtcHistoryRepository();
  final TripSummaryRepository tripSummaryRepository = TripSummaryRepository();
  final DataLoggerService dataLoggerService = DataLoggerService();
  final FuelCalibrationRepository _fuelCalibrationRepository =
      FuelCalibrationRepository();

  Elm327Session? _session;
  LiveTelemetryService? _telemetry;
  StreamSubscription<VehicleState>? _telemetrySub;
  StreamSubscription<ElmSessionState>? _stateSub;
  Timer? _connectionWatch;
  bool? _lastTransportConnected;
  String? _deviceLabel;
  bool _isConnecting = false;
  bool _reposLoaded = false;
  bool _archivedForDisconnect = false;
  final List<TripPoint> _currentTripPoints = [];
  DateTime _tripStartedAt = DateTime.now();

  Elm327Session? get session => _session;
  LiveTelemetryService? get telemetryService => _telemetry;
  String? get deviceLabel => _deviceLabel;
  bool get isConnecting => _isConnecting;
  bool get isConnected => _session != null && _session!.isConnected;
  List<TripPoint> get currentTripPoints => _currentTripPoints;

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
    await ReportArchiveService.instance.beginSession();
    _archivedForDisconnect = false;

    final telemetry = LiveTelemetryService(session);
    _telemetry = telemetry;
    _telemetrySub = telemetry.stream.listen(_onVehicleState);
    _stateSub = session.stateStream.listen((_) => notifyListeners());
    _lastTransportConnected = session.isConnected;
    _connectionWatch?.cancel();
    _connectionWatch = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final connected = session.isConnected;
      if (connected == _lastTransportConnected) return;
      _lastTransportConnected = connected;
      notifyListeners();
    });
    await dataLoggerService.start();
    telemetry.start();
    notifyListeners();
  }

  void _onVehicleState(VehicleState state) {
    dataLoggerService.record(state);
    if (!state.connected) {
      _archiveOnDisconnect();
      return;
    }
    final point = TripPoint(
      timestamp: state.lastUpdate,
      rpm: state['rpm']?.round(),
      speedKmh: state['speed']?.round(),
      coolantTempC: state['coolant_temp']?.round(),
    );
    tripLogService.addPoint(point);
    _currentTripPoints.add(point);
  }

  Future<void> disconnect() async {
    await _teardown();
    notifyListeners();
  }

  Future<bool> reconnect() async {
    final session = _session;
    if (session == null) return false;
    setConnecting(true);
    try {
      final ok = await session.attemptReconnect();
      if (ok && _archivedForDisconnect) {
        session.rawCapture.clear();
        await ReportArchiveService.instance.beginSession();
        await dataLoggerService.start();
        _archivedForDisconnect = false;
      }
      notifyListeners();
      return ok;
    } finally {
      setConnecting(false);
    }
  }

  Future<void> _archiveOnDisconnect() async {
    if (_archivedForDisconnect || _session == null) return;
    _archivedForDisconnect = true;
    final session = _session!;
    final rawCaptureJson = session.rawCapture.toJson();
    await dataLoggerService.stop();
    await ReportArchiveService.instance.finalizeSession(
      rawCaptureJson: rawCaptureJson,
      csvFile: dataLoggerService.currentFile,
    );
    notifyListeners();
  }

  Future<void> _teardown() async {
    final session = _session;
    final telemetry = _telemetry;
    final rawCaptureJson = session?.rawCapture.toJson();
    await _telemetrySub?.cancel();
    await _stateSub?.cancel();
    _connectionWatch?.cancel();
    _connectionWatch = null;
    _lastTransportConnected = null;
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
        // The transport may already be disconnected.
      }
      session.dispose();
    }

    await dataLoggerService.stop();

    await tripLogService.flush();
    await _saveTripSummaryIfNeeded();
    if (session != null && rawCaptureJson != null && !_archivedForDisconnect) {
      await ReportArchiveService.instance.finalizeSession(
        rawCaptureJson: rawCaptureJson,
        csvFile: dataLoggerService.currentFile,
      );
    }
    await ReportArchiveService.instance.resetSession();
    _archivedForDisconnect = false;
    _currentTripPoints.clear();
  }

  Future<void> _saveTripSummaryIfNeeded() async {
    if (_currentTripPoints.length < 2) return;
    final stats = TripComputer.compute(
      List<TripPoint>.of(_currentTripPoints),
      fuelConsumptionLPer100Km:
          _fuelCalibrationRepository.currentRateLPer100Km,
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
