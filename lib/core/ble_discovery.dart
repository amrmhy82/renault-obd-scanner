import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// جهاز BLE مكتشف، بصيغة مبسّطة تحجب أنواع المكتبة عن الشاشات.
class BleFoundDevice {
  final String id;
  final String name;
  final int rssi;
  final bool isLikelyObd;
  final BluetoothDevice device;

  const BleFoundDevice({
    required this.id,
    required this.name,
    required this.rssi,
    required this.isLikelyObd,
    required this.device,
  });
}

/// بحث عن أجهزة BLE قريبة. محولات ELM327 من نوع BLE **لا تظهر عادة في
/// إعدادات بلوتوث الجوال** (أندرويد يُخفي أجهزة LE-only من قائمة الإقران)،
/// ولا تحتاج إقرانًا أصلًا — لذلك يجب أن يبحث التطبيق عنها بنفسه ويتصل بها
/// مباشرة، وهذا ما يفعله هذا الكلاس.
class BleDiscovery {
  static final RegExp _obdNameHint = RegExp(
    r'(obd|elm|v-?link|vgate|icar|veepeak|viecar|konnwei|carista|carly|scan)',
    caseSensitive: false,
  );

  /// يعرض تراكم نتائج البحث الجاري (المكتبة تُصدر القائمة الكاملة كل مرة).
  Stream<List<BleFoundDevice>> get results =>
      FlutterBluePlus.scanResults.map((list) {
        final out = list.map((r) {
          final adv = r.advertisementData.advName;
          final name = adv.isNotEmpty ? adv : r.device.platformName;
          return BleFoundDevice(
            id: r.device.remoteId.str,
            name: name,
            rssi: r.rssi,
            isLikelyObd: _obdNameHint.hasMatch(name),
            device: r.device,
          );
        }).toList();
        // المرجّحة كمحولات OBD أولًا، ثم الأقوى إشارة
        out.sort((a, b) {
          if (a.isLikelyObd != b.isLikelyObd) return a.isLikelyObd ? -1 : 1;
          return b.rssi.compareTo(a.rssi);
        });
        return out;
      });

  Stream<bool> get isScanning => FlutterBluePlus.isScanning;

  /// يتأكد أن البلوتوث مشغَّل (ويطلب تشغيله على أندرويد إن لزم).
  Future<bool> ensureAdapterOn() async {
    try {
      final current = await FlutterBluePlus.adapterState.first
          .timeout(const Duration(seconds: 3));
      if (current == BluetoothAdapterState.on) return true;
      await FlutterBluePlus.turnOn();
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 10));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> startScan({Duration timeout = const Duration(seconds: 12)}) {
    return FlutterBluePlus.startScan(timeout: timeout);
  }

  Future<void> stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}
  }
}
