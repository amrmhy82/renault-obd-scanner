import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';

/// عمليات اكتشاف/إقران/تفعيل البلوتوث — منفصلة عن Transport لأنها لا تخص
/// اتصالًا محددًا بل حالة جهاز المستخدم نفسه.
///
/// ملاحظة تقنية مهمة: بلوتوث Classic/SPP على أندرويد **يتطلب إقران
/// (Bonding) على مستوى نظام التشغيل** قبل أن يقدر أي تطبيق يفتح اتصال
/// RFCOMM معه — هذا قيد أمني من أندرويد نفسه وليس قصورًا في هذا التطبيق،
/// ولا يمكن تجاوزه بالكامل. ما نقدر نفعله فعليًا هو جلب عملية الإقران
/// **داخل** التطبيق (بدل تحويل المستخدم لإعدادات الجوال يدويًا)، عبر
/// bondDeviceAtAddress التي تُظهر حوار إقران أندرويد كنافذة منبثقة فوق
/// شاشتنا مباشرة، دون الخروج من التطبيق.
class BluetoothClassicDiscovery {
  /// صلاحيات وقت التشغيل المطلوبة للبحث/الاتصال ببلوتوث كلاسيك على
  /// أندرويد 12+ (BLUETOOTH_SCAN/CONNECT) وأندرويد الأقدم (الموقع). بدون
  /// هذا الطلب الصريح، يرجع startDiscovery فارغًا بصمت على كثير من الأجهزة.
  Future<bool> requestRuntimePermissions() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
    return statuses.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<bool> requestEnableBluetooth() async {
    await requestRuntimePermissions();
    final isEnabled = await FlutterBluetoothSerial.instance.isEnabled;
    if (isEnabled == true) return true;
    final result = await FlutterBluetoothSerial.instance.requestEnable();
    return result == true;
  }

  Future<List<BluetoothDevice>> getPairedDevices() async {
    return await FlutterBluetoothSerial.instance.getBondedDevices();
  }

  /// يبدأ بحثًا عن أجهزة بلوتوث قريبة (مقترنة وغير مقترنة). يُرجع Stream
  /// تُصدر كل جهاز يُكتشف تباعًا؛ ينتهي تلقائيًا بعد ~12 ثانية على أندرويد،
  /// أو استدعِ cancelDiscovery() لإيقافه يدويًا قبل ذلك.
  Stream<BluetoothDiscoveryResult> startDiscovery() {
    return FlutterBluetoothSerial.instance.startDiscovery();
  }

  Future<void> cancelDiscovery() async {
    try {
      await FlutterBluetoothSerial.instance.cancelDiscovery();
    } catch (_) {}
  }

  /// يطلب إقران جهاز غير مقترن — يُظهر حوار أندرويد (طلب PIN أو تأكيد) فوق
  /// شاشة التطبيق مباشرة. لا نقدر نتحكم بشكل هذا الحوار، فهو جزء من نظام
  /// التشغيل، لكن على الأقل لا يحتاج المستخدم مغادرة التطبيق للوصول له.
  Future<bool> bondDevice(String address) async {
    try {
      final bonded = await FlutterBluetoothSerial.instance.bondDeviceAtAddress(address);
      return bonded == true;
    } catch (_) {
      return false;
    }
  }
}
