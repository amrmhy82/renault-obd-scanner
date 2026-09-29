import 'package:flutter/material.dart';
import '../core/obd_connection_controller.dart';
import '../debug/debug_log_screen.dart';
import '../health/health_score_screen.dart';
import '../maintenance/maintenance_screen.dart';
import '../trip/fuel_calibration_screen.dart';
import '../trip/trip_computer_screen.dart';
import '../vehicle/vehicle_profile_repository.dart';
import '../vehicle/vehicle_profile_screen.dart';
import 'dashboard_screen.dart';
import 'data_logs_screen.dart';
import 'dtc_screen.dart';
import 'scan_screen.dart';
import 'trip_log_screen.dart';

/// الشاشة الرئيسية الفعلية للتطبيق — تُفتح دائمًا بلا شرط اتصال. الاتصال
/// بالمحول أصبح إجراءً اختياريًا يُطلب من هنا (بطاقة الحالة أعلى الشاشة)،
/// وليس بوابة إجبارية قبل الوصول لأي شيء كما كان سابقًا.
class HomeScreen extends StatefulWidget {
  final ObdConnectionController controller;
  const HomeScreen({super.key, required this.controller});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final VehicleProfileRepository _profileRepo = VehicleProfileRepository();
  String _title = 'Matal Fluence Scan';

  @override
  void initState() {
    super.initState();
    widget.controller.loadReposIfNeeded();
    _loadTitle();
  }

  Future<void> _loadTitle() async {
    await _profileRepo.load();
    final p = _profileRepo.profile;
    if (mounted) {
      setState(() => _title = '${p.make} ${p.model}${p.year != null ? " ${p.year}" : ""}');
    }
  }

  Future<void> _openScan() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ScanScreen(controller: widget.controller)),
    );
  }

  void _openIfConnected(Widget Function() builder) {
    if (!widget.controller.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يحتاج اتصالًا نشطًا بالمحول أولًا — اضغط "اتصال" أعلى الشاشة')),
      );
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => builder()));
  }

  Widget _statusCard(ObdConnectionController c) {
    final connected = c.isConnected;
    return Card(
      color: connected ? Colors.green.shade50 : Colors.blueGrey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: connected ? Colors.green.shade700 : Colors.blueGrey,
              size: 32,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    connected ? 'متصل بالمحول' : 'غير متصل',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  if (connected && c.deviceLabel != null)
                    Text(c.deviceLabel!, style: const TextStyle(color: Colors.grey, fontSize: 12))
                  else if (!connected)
                    const Text('يمكنك تصفح باقي الشاشات بدون اتصال',
                        style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
            if (c.isConnecting)
              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            else
              TextButton(
                onPressed: connected ? c.disconnect : _openScan,
                child: Text(connected ? 'قطع الاتصال' : 'اتصال'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _menuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: enabled ? Colors.blueGrey : Colors.grey.shade400),
        title: Text(title, style: TextStyle(color: enabled ? null : Colors.grey)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_left),
        onTap: onTap,
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          final connected = c.isConnected;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _statusCard(c),
              const SizedBox(height: 20),

              _sectionLabel('يحتاج اتصالًا نشطًا'),
              _menuTile(
                icon: Icons.speed,
                title: 'البيانات الحية',
                subtitle: 'دورات المحرك، السرعة، الحرارة، حساسات الاحتراق...',
                enabled: connected,
                onTap: () => _openIfConnected(
                  () => DashboardScreen(
                    session: c.session!,
                    telemetryService: c.telemetryService!,
                    tripLogService: c.tripLogService,
                    dtcHistoryRepository: c.dtcHistoryRepository,
                    tripSummaryRepository: c.tripSummaryRepository,
                  ),
                ),
              ),
              _menuTile(
                icon: Icons.warning_amber_rounded,
                title: 'أعطال المحرك (DTC)',
                subtitle: 'فحص جديد، مسح، والسجل التاريخي',
                enabled: connected,
                onTap: () => _openIfConnected(
                  () => DtcScreen(session: c.session!, historyRepository: c.dtcHistoryRepository),
                ),
              ),
              _menuTile(
                icon: Icons.health_and_safety,
                title: 'حالة السيارة',
                subtitle: 'تقييم مبني على القراءات الحية الآن',
                enabled: connected,
                onTap: () => _openIfConnected(
                  () => HealthScoreScreen(session: c.session!, telemetryService: c.telemetryService!),
                ),
              ),
              _menuTile(
                icon: Icons.bug_report_outlined,
                title: 'سجل التصحيح (Debug)',
                subtitle: 'كل أمر أُرسل والرد الخام له',
                enabled: connected,
                onTap: () => _openIfConnected(() => DebugLogScreen(session: c.session!)),
              ),

              const SizedBox(height: 12),
              _sectionLabel('متاح دائمًا — بدون اتصال'),
              _menuTile(
                icon: Icons.route,
                title: 'حاسبة الرحلة',
                subtitle: 'إحصاءات الرحلة الحالية والرحلات السابقة',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TripComputerScreen(
                    getCurrentTripPoints: () => c.currentTripPoints,
                    tripSummaryRepository: c.tripSummaryRepository,
                  ),
                )),
              ),
              _menuTile(
                icon: Icons.show_chart,
                title: 'سجل الرحلة (رسوم بيانية)',
                subtitle: 'RPM والسرعة والحرارة عبر الزمن',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => TripLogScreen(tripLogService: c.tripLogService),
                )),
              ),
              _menuTile(
                icon: Icons.description_outlined,
                title: 'سجل البيانات الكامل (CSV)',
                subtitle: 'كل الحساسات، ملف منفصل لكل جلسة',
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const DataLogsScreen())),
              ),
              _menuTile(
                icon: Icons.local_gas_station,
                title: 'معايرة استهلاك الوقود',
                subtitle: 'أدخل تعبئاتك الفعلية لتقدير أدق',
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const FuelCalibrationScreen())),
              ),
              _menuTile(
                icon: Icons.build,
                title: 'سجل الصيانة',
                subtitle: 'زيت، فلاتر، بوجيهات، عداد الكيلومترات...',
                onTap: () => Navigator.of(context)
                    .push(MaterialPageRoute(builder: (_) => const MaintenanceScreen())),
              ),
              _menuTile(
                icon: Icons.directions_car,
                title: 'بيانات السيارة',
                subtitle: 'الموديل، VIN، العداد الحالي...',
                onTap: () async {
                  await Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const VehicleProfileScreen()));
                  _loadTitle();
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
