import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

/// عمليات اكتشاف/إقران/تفعيل البلوتوث **الكلاسيك (SPP)** — منفصلة عن
/// Transport لأنها لا تخص اتصالًا محددًا بل حالة جهاز المستخدم نفسه.
///
/// الصلاحيات تُدار الآن في `BluetoothPermissions` (تُستدعى من الشاشة قبل أي
/// دالة هنا)، فلا تُطلب داخل هذا الكلاس ولا تُتجاهل نتائجها.
///
/// ملاحظة تقنية: بلوتوث Classic/SPP على أندرويد يتطلب إقران (Bonding) على
/// مستوى النظام قبل الاتصال. ما نقدر نفعله هو تشغيل الإقران من داخل التطبيق
/// عبر bondDeviceAtAddress (حوار PIN يظهر من نظام أندرويد فوق شاشتنا).
class BluetoothClassicDiscovery {
  /// يفترض أن BLUETOOTH_CONNECT ممنوحة مسبقًا.
  Future<bool> requestEnableBluetooth() async {
    final isEnabled = await FlutterBluetoothSerial.instance.isEnabled;
    if (isEnabled == true) return true;
    final result = await FlutterBluetoothSerial.instance.requestEnable();
    return result == true;
  }

  Future<List<BluetoothDevice>> getPairedDevices() async {
    return await FlutterBluetoothSerial.instance.getBondedDevices();
  }

  Stream<BluetoothDiscoveryResult> startDiscovery() {
    return FlutterBluetoothSerial.instance.startDiscovery();
  }

  Future<void> cancelDiscovery() async {
    try {
      await FlutterBluetoothSerial.instance.cancelDiscovery();
    } catch (_) {}
  }

  Future<bool> bondDevice(String address) async {
    try {
      final bonded = await FlutterBluetoothSerial.instance.bondDeviceAtAddress(address);
      return bonded == true;
    } catch (_) {
      return false;
    }
  }
}
