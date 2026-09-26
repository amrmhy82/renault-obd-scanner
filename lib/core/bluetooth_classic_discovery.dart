import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

/// عمليات اكتشاف/تفعيل البلوتوث — منفصلة عن Transport لأنها لا تخص
/// اتصالًا محددًا بل حالة جهاز المستخدم نفسه.
class BluetoothClassicDiscovery {
  Future<bool> requestEnableBluetooth() async {
    final isEnabled = await FlutterBluetoothSerial.instance.isEnabled;
    if (isEnabled == true) return true;
    final result = await FlutterBluetoothSerial.instance.requestEnable();
    return result == true;
  }

  Future<List<BluetoothDevice>> getPairedDevices() async {
    return await FlutterBluetoothSerial.instance.getBondedDevices();
  }
}
