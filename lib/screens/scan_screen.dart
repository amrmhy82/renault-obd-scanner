import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import '../core/bluetooth_classic_discovery.dart';
import '../core/bluetooth_classic_transport.dart';
import '../core/elm327_session.dart';
import '../diagnostics/dtc_history_repository.dart';
import '../services/trip_log_service.dart';
import '../telemetry/live_telemetry_service.dart';
import '../trip/trip_summary_repository.dart';
import 'dashboard_screen.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final BluetoothClassicDiscovery _discovery = BluetoothClassicDiscovery();
  final TripLogService _tripLogService = TripLogService();
  final DtcHistoryRepository _dtcHistoryRepository = DtcHistoryRepository();
  final TripSummaryRepository _tripSummaryRepository = TripSummaryRepository();

  List<BluetoothDevice> _devices = [];
  bool _loading = false;
  String? _connectingAddress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPairedDevices();
  }

  Future<void> _loadPairedDevices() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _discovery.requestEnableBluetooth();
      final devices = await _discovery.getPairedDevices();
      setState(() => _devices = devices);
    } catch (e) {
      setState(() => _error = 'تعذّر جلب الأجهزة المقترنة: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() {
      _connectingAddress = device.address;
      _error = null;
    });

    final transport = BluetoothClassicTransport(device);
    final ok = await transport.connect();
    if (!ok) {
      setState(() {
        _connectingAddress = null;
        _error =
            'فشل الاتصال بـ ${device.name ?? device.address}. تأكد أن المحول موصول بمنفذ OBD2 والسيارة في وضع التشغيل (Ignition ON).';
      });
      return;
    }

    final session = Elm327Session(transport);
    try {
      await session.initialize();
    } catch (e) {
      setState(() {
        _connectingAddress = null;
        _error = 'تم الاتصال لكن تعذّرت تهيئة المحول: $e';
      });
      return;
    }

    await _dtcHistoryRepository.load();

    final telemetry = LiveTelemetryService(session);
    telemetry.start();

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DashboardScreen(
          session: session,
          telemetryService: telemetry,
          tripLogService: _tripLogService,
          dtcHistoryRepository: _dtcHistoryRepository,
          tripSummaryRepository: _tripSummaryRepository,
        ),
      ),
    );
    setState(() => _connectingAddress = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اختر محول OBD2')),
      body: RefreshIndicator(
        onRefresh: _loadPairedDevices,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'قبل المتابعة: أقرن محول ELM327 من إعدادات البلوتوث في جوالك '
              '(كلمة المرور غالبًا 1234 أو 0000)، ثم شغّل السيارة، وارجع هنا.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            if (_loading) const Center(child: CircularProgressIndicator()),
            if (!_loading && _devices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('لا توجد أجهزة مقترنة. أقرن المحول أولًا من إعدادات الجوال.'),
              ),
            ..._devices.map((d) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.bluetooth),
                    title: Text(d.name ?? 'جهاز غير معروف'),
                    subtitle: Text(d.address),
                    trailing: _connectingAddress == d.address
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_left),
                    onTap: _connectingAddress == null ? () => _connect(d) : null,
                  ),
                )),
          ],
        ),
      ),
    );
  }
}
