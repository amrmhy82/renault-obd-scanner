import 'dart:async';
import 'package:flutter/material.dart';
import '../core/elm327_session.dart';
import '../core/elm_session_state.dart';
import '../core/pid_registry.dart';
import '../debug/debug_log_screen.dart';
import '../diagnostics/dtc_history_repository.dart';
import '../health/health_score_screen.dart';
import '../maintenance/maintenance_screen.dart';
import '../models/trip_point.dart';
import '../services/trip_log_service.dart';
import '../telemetry/live_telemetry_service.dart';
import '../telemetry/vehicle_state.dart';
import '../trip/trip_computer.dart';
import '../trip/trip_computer_screen.dart';
import '../trip/trip_summary.dart';
import '../trip/trip_summary_repository.dart';
import '../trip/fuel_calibration_repository.dart';
import '../vehicle/vehicle_profile_repository.dart';
import '../vehicle/vehicle_profile_screen.dart';
import 'dtc_screen.dart';
import 'trip_log_screen.dart';
import '../trip/fuel_calibration_screen.dart';
import '../data/data_logger_service.dart';
import 'data_logs_screen.dart';

/// لا تعرف هذه الشاشة أي شيء عن ELM327 أو أوامر AT/PID — هي فقط "مستهلك"
/// (Consumer) لتيار VehicleState وحالة الجلسة القادمين من الطبقات الأدنى.
class DashboardScreen extends StatefulWidget {
  final Elm327Session session;
  final LiveTelemetryService telemetryService;
  final TripLogService tripLogService;
  final DtcHistoryRepository dtcHistoryRepository;
  final TripSummaryRepository tripSummaryRepository;

  const DashboardScreen({
    super.key,
    required this.session,
    required this.telemetryService,
    required this.tripLogService,
    required this.dtcHistoryRepository,
    required this.tripSummaryRepository,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  StreamSubscription<VehicleState>? _sub;
  StreamSubscription<ElmSessionState>? _sessionSub;
  VehicleState _state = VehicleState.initial();
  ElmSessionState _sessionState = ElmSessionState.disconnected;

  final VehicleProfileRepository _profileRepository = VehicleProfileRepository();
  final FuelCalibrationRepository _fuelCalibrationRepository = FuelCalibrationRepository();
  final DataLoggerService _dataLogger = DataLoggerService();
  String _title = 'بيانات حية';

  final List<TripPoint> _currentTripPoints = [];
  final DateTime _tripStartedAt = DateTime.now();
  bool _tripSaved = false;

  @override
  void initState() {
    super.initState();
    _sessionState = widget.session.state;
    widget.tripLogService.load();
    widget.tripSummaryRepository.load();
    _fuelCalibrationRepository.load();
    _loadProfileTitle();
    _sub = widget.telemetryService.stream.listen(_onState);
    _dataLogger.start();
    _sessionSub = widget.session.stateStream.listen((s) {
      if (mounted) setState(() => _sessionState = s);
    });
  }

  Future<void> _loadProfileTitle() async {
    await _profileRepository.load();
    final p = _profileRepository.profile;
    if (mounted) {
      setState(() => _title = '${p.make} ${p.model}${p.year != null ? " ${p.year}" : ""}');
    }
  }

  void _onState(VehicleState state) {
    if (!mounted) return;
    setState(() => _state = state);
    _dataLogger.record(state);
    final point = TripPoint(
      timestamp: state.lastUpdate,
      rpm: state['rpm']?.round(),
      speedKmh: state['speed']?.round(),
      coolantTempC: state['coolant_temp']?.round(),
    );
    widget.tripLogService.addPoint(point);
    _currentTripPoints.add(point);
  }

  Future<void> _saveTripSummaryIfNeeded() async {
    if (_tripSaved || _currentTripPoints.length < 2) return;
    _tripSaved = true;
    final stats = TripComputer.compute(
      _currentTripPoints,
      fuelConsumptionLPer100Km: _fuelCalibrationRepository.currentRateLPer100Km,
      isCalibratedRate: _fuelCalibrationRepository.isCalibrated,
    );
    if (stats.pointCount < 2) return;
    await widget.tripSummaryRepository.addTrip(TripSummary(
      id: _tripStartedAt.millisecondsSinceEpoch.toString(),
      startedAt: _tripStartedAt,
      endedAt: DateTime.now(),
      stats: stats,
    ));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _sessionSub?.cancel();
    widget.telemetryService.dispose();
    widget.session.transport.disconnect();
    widget.session.dispose();
    // عمليات غير متزامنة (dispose لا يمكن أن يكون async): كتابة فورية لأي
    // بيانات رحلة متبقية بدل انتظار دورة الحفظ الدفعي التالية، ثم حفظ ملخص
    // الرحلة.
    widget.tripLogService.flushAndClose();
    _saveTripSummaryIfNeeded();
    _dataLogger.stop();
    super.dispose();
  }

  IconData _iconFor(String key) {
    switch (key) {
      case 'rpm':
        return Icons.speed;
      case 'speed':
        return Icons.directions_car;
      case 'coolant_temp':
        return Icons.thermostat;
      case 'engine_load':
        return Icons.bolt;
      case 'throttle':
        return Icons.tune;
      case 'iat':
        return Icons.air;
      case 'fuel_level':
        return Icons.local_gas_station;
      case 'map':
        return Icons.compress;
      case 'o2_b1s1':
        return Icons.sensors;
      case 'timing_advance':
        return Icons.settings_suggest;
      case 'battery_voltage':
        return Icons.battery_charging_full;
      case 'absolute_load':
        return Icons.bar_chart;
      case 'stft_b1':
        return Icons.trending_up;
      case 'ltft_b1':
        return Icons.trending_flat;
      case 'o2_b1s1':
        return Icons.sensors;
      case 'o2_b1s2':
        return Icons.thermostat_auto;
      case 'cmd_throttle':
        return Icons.swap_horiz;
      case 'equiv_ratio':
        return Icons.science;
      case 'fuel_rail_rel':
        return Icons.gas_meter;
      default:
        return Icons.info_outline;
    }
  }

  String _formatValue(num? v) {
    if (v == null) return '--';
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(2);
  }

  Widget _card(String label, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Colors.blueGrey),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  String? _sessionBanner() {
    switch (_sessionState) {
      case ElmSessionState.disconnected:
        return 'غير متصل';
      case ElmSessionState.connecting:
        return 'جارٍ الاتصال بالمحول...';
      case ElmSessionState.initializing:
        return 'جارٍ تهيئة المحول...';
      case ElmSessionState.detectingProtocol:
        return 'جارٍ تحديد بروتوكول السيارة...';
      case ElmSessionState.reconnecting:
        return 'جارٍ إعادة الاتصال...';
      case ElmSessionState.communicationError:
        return 'خطأ في الاتصال بالمحول';
      case ElmSessionState.ready:
        return _state.connected ? null : 'انقطع الاتصال بالمحول';
    }
  }

  void _openMenuItem(String key) {
    switch (key) {
      case 'trip_log':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TripLogScreen(tripLogService: widget.tripLogService),
        ));
        break;
      case 'trip_computer':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TripComputerScreen(
            getCurrentTripPoints: () => _currentTripPoints,
            tripSummaryRepository: widget.tripSummaryRepository,
          ),
        ));
        break;
      case 'health':
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => HealthScoreScreen(
            session: widget.session,
            telemetryService: widget.telemetryService,
          ),
        ));
        break;
      case 'maintenance':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MaintenanceScreen()));
        break;
      case 'vehicle_profile':
        Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const VehicleProfileScreen()))
            .then((_) => _loadProfileTitle());
        break;
      case 'debug':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => DebugLogScreen(session: widget.session)));
        break;
      case 'fuel_calibration':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FuelCalibrationScreen()));
        break;
      case 'data_logs':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DataLogsScreen()));
        break;
    }
  }

  Widget _pidGrid(List<PidDefinition> pids) {
    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 1.3,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: pids.map((pid) {
        final value = _state[pid.key];
        return _card(pid.nameAr, '${_formatValue(value)} ${pid.unit}', _iconFor(pid.key));
      }).toList(),
    );
  }

  Widget _sectionHeader(String titleAr, IconData icon, int count) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: Colors.blueGrey.shade700),
          const SizedBox(width: 8),
          Text(titleAr, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.blueGrey.shade700)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(10)),
            child: Text('$count', style: TextStyle(fontSize: 12, color: Colors.blueGrey.shade700)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final banner = _sessionBanner();
    final basics = PidRegistry.byCategory(PidCategory.basics);
    final combustion = PidRegistry.byCategory(PidCategory.combustion);
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            icon: const Icon(Icons.warning_amber_rounded),
            tooltip: 'أعطال المحرك (DTC)',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => DtcScreen(
                  session: widget.session,
                  historyRepository: widget.dtcHistoryRepository,
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: _openMenuItem,
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'health', child: Text('حالة السيارة')),
              PopupMenuItem(value: 'trip_computer', child: Text('حاسبة الرحلة')),
              PopupMenuItem(value: 'fuel_calibration', child: Text('معايرة استهلاك الوقود')),
              PopupMenuItem(value: 'trip_log', child: Text('سجل الرحلة (رسوم بيانية)')),
              PopupMenuItem(value: 'data_logs', child: Text('سجل البيانات الكامل (CSV)')),
              PopupMenuItem(value: 'maintenance', child: Text('سجل الصيانة')),
              PopupMenuItem(value: 'vehicle_profile', child: Text('بيانات السيارة')),
              PopupMenuDivider(),
              PopupMenuItem(value: 'debug', child: Text('سجل التصحيح (Debug)')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          if (banner != null)
            Container(
              width: double.infinity,
              color: _sessionState == ElmSessionState.communicationError
                  ? Colors.red.shade50
                  : Colors.blueGrey.shade50,
              padding: const EdgeInsets.all(12),
              child: Text(
                banner,
                style: TextStyle(
                  color: _sessionState == ElmSessionState.communicationError
                      ? Colors.red
                      : Colors.blueGrey.shade700,
                ),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                _sectionHeader('البيانات الأساسية', Icons.dashboard, basics.length),
                _pidGrid(basics),
                const SizedBox(height: 24),
                _sectionHeader('حساسات الاحتراق والوقود', Icons.local_fire_department, combustion.length),
                _pidGrid(combustion),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'ملاحظة: ظهور "--" لأي قياس بعد اتصال كافٍ يعني أن وحدة الحقن '
                    'في سيارتك لا تُبلّغ عن هذا PID تحديدًا. هذا ليس خللًا في '
                    'التطبيق — راجع "سجل التصحيح (Debug)" لرؤية الرد الخام للتأكد.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
