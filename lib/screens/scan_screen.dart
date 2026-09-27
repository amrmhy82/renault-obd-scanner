import 'dart:async';
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

  List<BluetoothDevice> _pairedDevices = [];
  final List<BluetoothDiscoveryResult> _discovered = [];
  StreamSubscription<BluetoothDiscoveryResult>? _discoverySub;

  bool _loadingPaired = false;
  bool _scanning = false;
  String? _connectingAddress;
  String? _bondingAddress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPairedDevices();
  }

  @override
  void dispose() {
    _discoverySub?.cancel();
    _discovery.cancelDiscovery();
    super.dispose();
  }

  Future<void> _loadPairedDevices() async {
    setState(() {
      _loadingPaired = true;
      _error = null;
    });
    try {
      await _discovery.requestEnableBluetooth();
      final devices = await _discovery.getPairedDevices();
      setState(() => _pairedDevices = devices);
    } catch (e) {
      setState(() => _error = 'تعذّر جلب الأجهزة المقترنة: $e');
    } finally {
      setState(() => _loadingPaired = false);
    }
  }

  /// بحث عن أجهزة قريبة (مقترنة وغير مقترنة) داخل الشاشة نفسها — بدل توجيه
  /// المستخدم لإعدادات بلوتوث الجوال.
  void _startScan() {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _discovered.clear();
      _error = null;
    });
    _discovery.requestRuntimePermissions().then((granted) {
      if (!mounted) return;
      if (!granted) {
        setState(() {
          _scanning = false;
          _error = 'التطبيق يحتاج صلاحية البلوتوث/الموقع للبحث عن أجهزة قريبة. '
              'فعّلها من إعدادات الجوال ← أذونات التطبيق، ثم أعد المحاولة.';
        });
        return;
      }
      _discoverySub?.cancel();
      _discoverySub = _discovery.startDiscovery().listen(
        (result) {
          if (!mounted) return;
          final alreadyPaired = _pairedDevices.any((d) => d.address == result.device.address);
          if (alreadyPaired) return;
          setState(() {
            final idx = _discovered.indexWhere((r) => r.device.address == result.device.address);
            if (idx >= 0) {
              _discovered[idx] = result;
            } else {
              _discovered.add(result);
            }
          });
        },
        onDone: () {
          if (mounted) setState(() => _scanning = false);
        },
        onError: (_) {
          if (mounted) setState(() => _scanning = false);
        },
      );
    });
  }

  Future<void> _stopScan() async {
    await _discoverySub?.cancel();
    await _discovery.cancelDiscovery();
    if (mounted) setState(() => _scanning = false);
  }

  /// يطلب إقران جهاز غير مقترن. حوار الإقران/PIN يظهر من نظام أندرويد نفسه
  /// فوق هذه الشاشة مباشرة — هذا أقصى ما يمكن "دمجه" داخل التطبيق، لأن
  /// أندرويد لا يسمح بتخطي هذا الحوار كليًا لاتصالات بلوتوث الكلاسيك.
  Future<void> _pairDevice(BluetoothDiscoveryResult result) async {
    setState(() {
      _bondingAddress = result.device.address;
      _error = null;
    });
    final ok = await _discovery.bondDevice(result.device.address);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _discovered.removeWhere((r) => r.device.address == result.device.address);
        _bondingAddress = null;
      });
      await _loadPairedDevices();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إقران ${result.device.name ?? result.device.address} بنجاح')),
        );
      }
    } else {
      setState(() {
        _bondingAddress = null;
        _error = 'فشل الإقران مع ${result.device.name ?? result.device.address}. '
            'تأكد أن المحول مُشغَّل وفي وضع الاستعداد للإقران (غالبًا ضوء يومض).';
      });
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

  Widget _pairedTile(BluetoothDevice d) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.bluetooth_connected, color: Colors.blue),
        title: Text(d.name ?? 'جهاز غير معروف'),
        subtitle: Text(d.address),
        trailing: _connectingAddress == d.address
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.chevron_left),
        onTap: _connectingAddress == null ? () => _connect(d) : null,
      ),
    );
  }

  Widget _discoveredTile(BluetoothDiscoveryResult r) {
    final isBonding = _bondingAddress == r.device.address;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.bluetooth, color: Colors.grey),
        title: Text(r.device.name?.isNotEmpty == true ? r.device.name! : 'جهاز غير مسمّى'),
        subtitle: Text(r.device.address),
        trailing: isBonding
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : TextButton(
                onPressed: () => _pairDevice(r),
                child: const Text('إقران'),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('اختر محول OBD2'),
        actions: [
          IconButton(
            icon: Icon(_scanning ? Icons.stop_circle_outlined : Icons.search),
            tooltip: _scanning ? 'إيقاف البحث' : 'بحث عن أجهزة قريبة',
            onPressed: _scanning ? _stopScan : _startScan,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadPairedDevices,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'شغّل محول ELM327 وضعه في وضع الإقران، ثم اضغط 🔍 أعلى الشاشة '
              'للبحث عنه وإقرانه من هنا مباشرة — بدون الخروج لإعدادات الجوال.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),

            Text('الأجهزة المقترنة (${_pairedDevices.length})',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_loadingPaired) const Center(child: CircularProgressIndicator()),
            if (!_loadingPaired && _pairedDevices.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('لا توجد أجهزة مقترنة بعد. ابحث عن محولك أدناه وأقرنه.'),
              ),
            ..._pairedDevices.map(_pairedTile),

            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('أجهزة قريبة غير مقترنة (${_discovered.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                if (_scanning)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (!_scanning && _discovered.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('اضغط أيقونة البحث 🔍 أعلى الشاشة لعرض الأجهزة القريبة.',
                    style: TextStyle(color: Colors.grey)),
              ),
            ..._discovered.map(_discoveredTile),
          ],
        ),
      ),
    );
  }
}
