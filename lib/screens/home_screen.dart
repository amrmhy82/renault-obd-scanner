import 'package:flutter/material.dart';
import '../core/obd_connection_controller.dart';
import '../telemetry/data_quality.dart';
import '../telemetry/vehicle_state.dart';
import '../debug/debug_log_screen.dart';
import '../health/health_score_screen.dart';
import '../maintenance/maintenance_screen.dart';
import '../trip/fuel_calibration_screen.dart';
import '../trip/trip_computer_screen.dart';
import '../vehicle/vehicle_profile_repository.dart';
import '../vehicle/vehicle_profile_screen.dart';
import 'dashboard_screen.dart';
import 'certification_screen.dart';
import 'data_logs_screen.dart';
import 'dtc_screen.dart';
import 'scan_screen.dart';
import 'symptom_screen.dart';
import 'quick_scan_screen.dart';
import 'trip_log_screen.dart';
import 'settings_screen.dart';
import 'renault_resource_capture_screen.dart';

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
      color: connected ? const Color(0xFFEAF5EE) : const Color(0xFFF3F1F1),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              connected ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
              color: connected ? const Color(0xFF2E7D52) : const Color(0xFF8A7775),
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
        leading: Icon(icon, color: enabled ? const Color(0xFF9E1B15) : Colors.grey.shade400),
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

  String _metricValue(VehicleState? state, String key, String unit) {
    final field = state?.field(key);
    if (field == null || field.value == null) return 'بانتظار القراءة';
    switch (field.quality) {
      case ValueQuality.stale:
        return 'بيانات قديمة';
      case ValueQuality.invalid:
        return 'قراءة غير صالحة';
      case ValueQuality.missing:
        return 'غير متاحة';
      case ValueQuality.degraded:
      case ValueQuality.good:
        final value = field.value!;
        final decimals = key == 'rpm' || key == 'speed' || key == 'coolant_temp' ? 0 : 1;
        return '${value.toStringAsFixed(decimals)} $unit';
    }
  }

  Widget _metricCard({
    required VehicleState? state,
    required String key,
    required String title,
    required String unit,
    required IconData icon,
  }) {
    final field = state?.field(key);
    final available = field?.value != null && field?.quality == ValueQuality.good;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF9E1B15), size: 24),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(color: Color(0xFF806F6D), fontSize: 12)),
            const SizedBox(height: 5),
            Text(
              _metricValue(state, key, unit),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: available ? 20 : 13,
                fontWeight: FontWeight.bold,
                color: available ? const Color(0xFF321B19) : const Color(0xFF9A8987),
              ),
            ),
            if (field != null && field.timestamp != null)
              Text(
                '${field.ageMs(DateTime.now())} ms • ${field.quality.labelAr}',
                style: const TextStyle(fontSize: 10, color: Color(0xFF9A8987)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _vehicleCard(VehicleProfileRepository profileRepo) {
    final profile = profileRepo.profile;
    return Card(
      color: const Color(0xFFFFF8F7),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: const Color(0xFFF5DEDB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.directions_car, color: Color(0xFF9E1B15), size: 32),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Renault Fluence', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(
                    '${profile.year ?? 'السنة غير محددة'} • ${profile.engine ?? 'المحرك غير محدد'}',
                    style: const TextStyle(color: Color(0xFF806F6D), fontSize: 12),
                  ),
                  const Text('Diagnostic & Vehicle Intelligence', style: TextStyle(color: Color(0xFF9E1B15), fontSize: 11)),
                ],
              ),
            ),
            IconButton(
              tooltip: 'بيانات السيارة',
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const VehicleProfileScreen())),
              icon: const Icon(Icons.chevron_left),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickCard({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, color: Colors.white, size: 25),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: const TextStyle(color: Color(0xFF806F6D), fontSize: 11)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left, color: Color(0xFF9E1B15)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _quickActions(ObdConnectionController c) {
    final connected = c.isConnected;
    final actions = [
      _quickCard(
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFF2387E8),
        title: 'قراءة الأعطال',
        subtitle: 'عرض ومسح أكواد الأعطال',
        onTap: () => _openIfConnected(() => DtcScreen(session: c.session!, historyRepository: c.dtcHistoryRepository)),
      ),
      _quickCard(
        icon: Icons.monitor_heart_outlined,
        color: const Color(0xFF16B879),
        title: 'البيانات الحية',
        subtitle: 'مراقبة الحساسات لحظيًا',
        onTap: () => _openIfConnected(() => DashboardScreen(
              session: c.session!,
              telemetryService: c.telemetryService!,
              tripLogService: c.tripLogService,
              dtcHistoryRepository: c.dtcHistoryRepository,
              tripSummaryRepository: c.tripSummaryRepository,
              getCurrentTripPoints: () => c.currentTripPoints,
              onReconnect: c.reconnect,
            )),
      ),
      _quickCard(
        icon: Icons.speed,
        color: const Color(0xFF7851D9),
        title: 'لوحة العدادات',
        subtitle: 'تخصيص وعرض البيانات',
        onTap: () => _openIfConnected(() => DashboardScreen(
              session: c.session!,
              telemetryService: c.telemetryService!,
              tripLogService: c.tripLogService,
              dtcHistoryRepository: c.dtcHistoryRepository,
              tripSummaryRepository: c.tripSummaryRepository,
              getCurrentTripPoints: () => c.currentTripPoints,
              onReconnect: c.reconnect,
            )),
      ),
      _quickCard(
        icon: Icons.route,
        color: const Color(0xFFF0444B),
        title: 'الرحلات',
        subtitle: 'تسجيل وتحليل الرحلات',
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripComputerScreen(
              getCurrentTripPoints: () => c.currentTripPoints,
              tripSummaryRepository: c.tripSummaryRepository,
            ))),
      ),
      _quickCard(
        icon: Icons.build_outlined,
        color: const Color(0xFFF39A19),
        title: 'الصيانة',
        subtitle: 'تذكيرات وإعادة ضبط الخدمة',
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MaintenanceScreen())),
      ),
      _quickCard(
        icon: Icons.settings_input_component,
        color: const Color(0xFF13B9D3),
        title: 'ناقل الحركة CVT',
        subtitle: connected ? 'بيانات Renault الخاصة غير متاحة' : 'يتطلب اتصالًا فعليًا',
        onTap: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('قراءة CVT الخاصة تحتاج تعريف ECU Renault موثقًا.')),
        ),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 3 : 1;
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 8,
          mainAxisSpacing: 2,
          childAspectRatio: columns == 3 ? 2.6 : 3.2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: actions,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: Image.asset('assets/icon/matal_logo.png'),
        ),
      ),
      body: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          final c = widget.controller;
          final connected = c.isConnected;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _vehicleCard(_profileRepo),
              const SizedBox(height: 8),
              _statusCard(c),
              const SizedBox(height: 8),
              _sectionLabel('المقاييس الأساسية'),
              LayoutBuilder(
                builder: (context, constraints) => GridView.count(
                crossAxisCount: constraints.maxWidth >= 900 ? 4 : 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 2,
                childAspectRatio: constraints.maxWidth >= 900 ? 1.05 : 1.35,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _metricCard(state: c.latestState, key: 'rpm', title: 'دورات المحرك', unit: 'RPM', icon: Icons.speed),
                  _metricCard(state: c.latestState, key: 'speed', title: 'السرعة', unit: 'كم/س', icon: Icons.directions_car),
                  _metricCard(state: c.latestState, key: 'coolant_temp', title: 'حرارة التبريد', unit: '°C', icon: Icons.thermostat),
                  _metricCard(state: c.latestState, key: 'adapter_voltage', title: 'جهد منفذ OBD', unit: 'V', icon: Icons.bolt),
                ],
              )),
              const SizedBox(height: 16),
              _sectionLabel('الاختصارات الرئيسية'),
              _quickActions(c),
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
                    getCurrentTripPoints: () => c.currentTripPoints,
                    onReconnect: c.reconnect,
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
                icon: Icons.assignment_turned_in_outlined,
                title: 'الفحص السريع',
                subtitle: 'تقرير الأعطال والجاهزية والقياسات الأساسية',
                enabled: connected,
                onTap: () => _openIfConnected(() => QuickScanScreen(session: c.session!)),
              ),
              _menuTile(
                icon: Icons.manage_search,
                title: 'مشاكل السيارة',
                subtitle: 'فحص موجّه حسب العرض مع تقرير الأدلة والاحتمالات',
                enabled: connected,
                onTap: () => _openIfConnected(() => SymptomScreen(session: c.session!)),
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
              _menuTile(
                icon: Icons.fact_check_outlined,
                title: 'اعتماد Phase 0',
                subtitle: 'تشغيل اختبارات الجاهزية وتصدير تقرير موثق',
                enabled: connected,
                onTap: () => _openIfConnected(() => CertificationScreen(session: c.session!)),
              ),
              _menuTile(
                icon: Icons.travel_explore,
                title: 'جمع موارد Renault',
                subtitle: 'حزمة قراءة فقط لبناء تعريفات السيارة لاحقًا',
                enabled: connected,
                onTap: () => _openIfConnected(() => RenaultResourceCaptureScreen(session: c.session!)),
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
              _menuTile(
                icon: Icons.settings_outlined,
                title: 'إعدادات التطبيق',
                subtitle: 'مجلد حفظ التقارير والحفظ التلقائي عند الانقطاع',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
