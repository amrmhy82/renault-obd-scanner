import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/ble_discovery.dart';
import '../core/ble_transport.dart';
import '../core/bluetooth_classic_discovery.dart';
import '../core/bluetooth_classic_transport.dart';
import '../core/bluetooth_permissions.dart';
import '../core/obd_connection_controller.dart';
import '../core/transport.dart';

/// نوع محول ELM327:
///  - ble: بلوتوث 4.0 منخفض الطاقة. لا يحتاج إقرانًا، ولا يظهر عادة في
///    إعدادات بلوتوث الجوال. (الأشيع في المحولات الصغيرة الحديثة)
///  - classic: بلوتوث كلاسيك SPP. يحتاج إقرانًا على مستوى النظام.
enum AdapterMode { ble, classic }

/// شاشة اختيار/إقران المحول فقط — لا تُفتح إلا بطلب صريح من الشاشة
/// الرئيسية (زر "اتصال")، وليست بوابة إجبارية لدخول التطبيق. عند نجاح
/// الاتصال تُغلق نفسها (pop) وترجع للرئيسية، والاتصال يستمر من هناك عبر
/// ObdConnectionController بغضّ النظر عمّا يُفتح بعدها.
class ScanScreen extends StatefulWidget {
  final ObdConnectionController controller;
  const ScanScreen({super.key, required this.controller});


  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  static const _modeKey = 'adapter_mode_v1';

  final BluetoothClassicDiscovery _classic = BluetoothClassicDiscovery();
  final BleDiscovery _ble = BleDiscovery();

  AdapterMode _mode = AdapterMode.ble;

  // كلاسيك
  List<BluetoothDevice> _pairedDevices = [];
  final List<BluetoothDiscoveryResult> _discovered = [];
  StreamSubscription<BluetoothDiscoveryResult>? _classicScanSub;
  bool _loadingPaired = false;
  String? _bondingAddress;

  // BLE
  List<BleFoundDevice> _bleDevices = [];
  StreamSubscription<List<BleFoundDevice>>? _bleResultsSub;
  StreamSubscription<bool>? _bleScanningSub;
  bool _showUnnamed = false;

  bool _scanning = false;
  String? _connectingKey;
  String? _error;
  bool _showSettingsButton = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_modeKey);
    if (saved == 'classic') _mode = AdapterMode.classic;
    if (mounted) setState(() {});
    if (_mode == AdapterMode.classic) await _loadPairedDevices();
  }

  @override
  void dispose() {
    _classicScanSub?.cancel();
    _bleResultsSub?.cancel();
    _bleScanningSub?.cancel();
    _classic.cancelDiscovery();
    _ble.stopScan();
    super.dispose();
  }

  Future<void> _setMode(AdapterMode m) async {
    if (m == _mode) return;
    await _stopScan();
    setState(() {
      _mode = m;
      _error = null;
      _showSettingsButton = false;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, m == AdapterMode.classic ? 'classic' : 'ble');
    if (m == AdapterMode.classic) await _loadPairedDevices();
  }

  void _showPermissionError() {
    setState(() {
      _error = BluetoothPermissions.deniedMessage;
      _showSettingsButton = true;
      _scanning = false;
    });
  }

  // ───────────────────────── كلاسيك ─────────────────────────

  Future<void> _loadPairedDevices() async {
    setState(() {
      _loadingPaired = true;
      _error = null;
      _showSettingsButton = false;
    });
    try {
      final perm = await BluetoothPermissions.ensureConnect();
      if (!perm.granted) {
        _showPermissionError();
        return;
      }
      await _classic.requestEnableBluetooth();
      final devices = await _classic.getPairedDevices();
      if (mounted) setState(() => _pairedDevices = devices);
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذّر جلب الأجهزة المقترنة: $e');
    } finally {
      if (mounted) setState(() => _loadingPaired = false);
    }
  }

  Future<void> _startClassicScan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _discovered.clear();
      _error = null;
      _showSettingsButton = false;
    });
    final perm = await BluetoothPermissions.ensureScan();
    if (!perm.granted) {
      _showPermissionError();
      return;
    }
    await _classic.requestEnableBluetooth();
    _classicScanSub?.cancel();
    _classicScanSub = _classic.startDiscovery().listen(
      (result) {
        if (!mounted) return;
        if (_pairedDevices.any((d) => d.address == result.device.address)) return;
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
  }

  Future<void> _pairDevice(BluetoothDiscoveryResult result) async {
    setState(() {
      _bondingAddress = result.device.address;
      _error = null;
    });
    final ok = await _classic.bondDevice(result.device.address);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _discovered.removeWhere((r) => r.device.address == result.device.address);
        _bondingAddress = null;
      });
      await _loadPairedDevices();
    } else {
      setState(() {
        _bondingAddress = null;
        _error = 'فشل الإقران مع ${result.device.name ?? result.device.address}. '
            'تأكد أن المحول مُشغَّل وفي وضع الاستعداد للإقران.';
      });
    }
  }

  // ───────────────────────── BLE ─────────────────────────

  Future<void> _startBleScan() async {
    if (_scanning) return;
    setState(() {
      _scanning = true;
      _bleDevices = [];
      _error = null;
      _showSettingsButton = false;
    });
    final perm = await BluetoothPermissions.ensureScan();
    if (!perm.granted) {
      _showPermissionError();
      return;
    }
    if (!await _ble.ensureAdapterOn()) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _error = 'البلوتوث مُطفأ. شغّله ثم أعد البحث.';
        });
      }
      return;
    }
    _bleResultsSub?.cancel();
    _bleResultsSub = _ble.results.listen((list) {
      if (mounted) setState(() => _bleDevices = list);
    });
    _bleScanningSub?.cancel();
    _bleScanningSub = _ble.isScanning.listen((s) {
      if (mounted && !s) setState(() => _scanning = false);
    });
    try {
      await _ble.startScan();
    } catch (e) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _error = 'تعذّر بدء بحث BLE: $e\n'
              'لو كانت خدمة الموقع (Location) مُطفأة فشغّلها — بعض الأجهزة تحتاجها للبحث.';
        });
      }
    }
  }

  // ───────────────────────── مشترك ─────────────────────────

  Future<void> _stopScan() async {
    await _classicScanSub?.cancel();
    await _classic.cancelDiscovery();
    await _ble.stopScan();
    if (mounted) setState(() => _scanning = false);
  }

  Future<void> _connectWith({
    required Transport transport,
    required String key,
    required String name,
  }) async {
    await _stopScan();
    setState(() {
      _connectingKey = key;
      _error = null;
      _showSettingsButton = false;
    });

    final ok = await transport.connect();
    if (!ok) {
      final detail = transport is BleTransport ? (transport.lastError ?? '') : '';
      setState(() {
        _connectingKey = null;
        _error = _mode == AdapterMode.ble
            ? 'فشل الاتصال بـ $name عبر BLE.\n'
                '• تأكد أن المحول غير متصل بجوال/تطبيق آخر (BLE يقبل اتصالًا واحدًا).\n'
                '• تأكد أن السيارة على وضع التشغيل (Ignition ON).\n'
                '${detail.isNotEmpty ? "\nتفاصيل تقنية: $detail" : ""}'
            : 'فشل الاتصال بـ $name. تأكد أن المحول موصول بمنفذ OBD2 والسيارة على وضع التشغيل (Ignition ON).';
      });
      return;
    }

    final session = Elm327Session(transport);
    try {
      await session.initialize();
    } catch (e) {
      await transport.disconnect();
      setState(() {
        _connectingKey = null;
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
    setState(() => _connectingKey = null);
  }

  // ───────────────────────── واجهة ─────────────────────────

  Widget _spinner() =>
      const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2));

  Widget _bleTile(BleFoundDevice d) {
    final title = d.name.isNotEmpty ? d.name : 'جهاز غير مسمّى';
    return Card(
      child: ListTile(
        leading: Icon(
          d.isLikelyObd ? Icons.star : Icons.bluetooth,
          color: d.isLikelyObd ? Colors.amber.shade700 : Colors.grey,
        ),
        title: Text(title),
        subtitle: Text('${d.id}  •  إشارة ${d.rssi} dBm'),
        trailing: _connectingKey == d.id ? _spinner() : const Icon(Icons.chevron_left),
        onTap: _connectingKey == null
            ? () => _connectWith(transport: BleTransport(d.device), key: d.id, name: title)
            : null,
      ),
    );
  }

  Widget _pairedTile(BluetoothDevice d) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.bluetooth_connected, color: Colors.blue),
        title: Text(d.name ?? 'جهاز غير معروف'),
        subtitle: Text(d.address),
        trailing: _connectingKey == d.address ? _spinner() : const Icon(Icons.chevron_left),
        onTap: _connectingKey == null
            ? () => _connectWith(
                  transport: BluetoothClassicTransport(d),
                  key: d.address,
                  name: d.name ?? d.address,
                )
            : null,
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
            ? _spinner()
            : TextButton(onPressed: () => _pairDevice(r), child: const Text('إقران')),
      ),
    );
  }

  List<Widget> _bleSection() {
    final visible = _showUnnamed ? _bleDevices : _bleDevices.where((d) => d.name.isNotEmpty).toList();
    return [
      const Text(
        'محولات BLE لا تحتاج إقرانًا ولا تظهر في إعدادات بلوتوث الجوال. '
        'شغّل المحول (موصولًا بالسيارة والمفتاح ON) ثم اضغط 🔍 واختره من القائمة مباشرة.',
        style: TextStyle(color: Colors.grey),
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('أجهزة BLE القريبة (${visible.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (_scanning) _spinner(),
        ],
      ),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('إظهار الأجهزة غير المسمّاة', style: TextStyle(fontSize: 13)),
        value: _showUnnamed,
        onChanged: (v) => setState(() => _showUnnamed = v ?? false),
      ),
      if (!_scanning && visible.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('اضغط 🔍 أعلى الشاشة للبحث. ⭐ = اسم يشبه محولات OBD.',
              style: TextStyle(color: Colors.grey)),
        ),
      ...visible.map(_bleTile),
    ];
  }

  List<Widget> _classicSection() {
    return [
      const Text(
        'المحولات الكلاسيكية (SPP) تحتاج إقرانًا: اضغط 🔍 لعرض الأجهزة القريبة ثم "إقران" '
        '(حوار الـ PIN يظهر من نظام أندرويد فوق التطبيق).',
        style: TextStyle(color: Colors.grey),
      ),
      const SizedBox(height: 16),
      Text('الأجهزة المقترنة (${_pairedDevices.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      if (_loadingPaired) const Center(child: CircularProgressIndicator()),
      if (!_loadingPaired && _pairedDevices.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('لا توجد أجهزة مقترنة بعد.'),
        ),
      ..._pairedDevices.map(_pairedTile),
      const SizedBox(height: 24),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('أجهزة قريبة غير مقترنة (${_discovered.length})',
              style: const TextStyle(fontWeight: FontWeight.bold)),
          if (_scanning) _spinner(),
        ],
      ),
      const SizedBox(height: 8),
      ..._discovered.map(_discoveredTile),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isBle = _mode == AdapterMode.ble;
    return Scaffold(
      appBar: AppBar(
        title: const Text('اختر محول OBD2'),
        actions: [
          IconButton(
            icon: Icon(_scanning ? Icons.stop_circle_outlined : Icons.search),
            tooltip: _scanning ? 'إيقاف البحث' : 'بحث',
            onPressed: _scanning ? _stopScan : (isBle ? _startBleScan : _startClassicScan),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (isBle) {
            await _startBleScan();
          } else {
            await _loadPairedDevices();
          }
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<AdapterMode>(
              segments: const [
                ButtonSegment(value: AdapterMode.ble, label: Text('BLE (بلوتوث 4.0)')),
                ButtonSegment(value: AdapterMode.classic, label: Text('كلاسيك (SPP)')),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => _setMode(s.first),
            ),
            const SizedBox(height: 16),
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_error!, style: TextStyle(color: Colors.red.shade800)),
                    if (_showSettingsButton)
                      TextButton(
                        onPressed: BluetoothPermissions.openSettings,
                        child: const Text('فتح إعدادات التطبيق'),
                      ),
                  ],
                ),
              ),
            ...(isBle ? _bleSection() : _classicSection()),
          ],
        ),
      ),
    );
  }
}
