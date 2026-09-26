import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'transport.dart';

/// تنفيذ [Transport] عبر بلوتوث كلاسيك (SPP) — وهو ما تدعمه أغلب محولات
/// ELM327 الرخيصة الشائعة. لإضافة دعم BLE أو واي فاي لاحقًا، يكفي إنشاء
/// كلاس جديد ينفّذ نفس الواجهة دون تعديل CommandQueue أو Elm327Session.
class BluetoothClassicTransport implements Transport {
  final BluetoothDevice device;
  BluetoothClassicTransport(this.device);

  BluetoothConnection? _connection;
  final StreamController<String> _dataController =
      StreamController<String>.broadcast();
  String _buffer = '';

  @override
  bool get isConnected => _connection != null && _connection!.isConnected;

  @override
  Future<bool> connect() async {
    try {
      _connection = await BluetoothConnection.toAddress(device.address);
      _connection!.input!.listen(
        _onData,
        onDone: () => _connection = null,
        onError: (_) => _connection = null,
      );
      return true;
    } catch (_) {
      _connection = null;
      return false;
    }
  }

  void _onData(Uint8List data) {
    _buffer += utf8.decode(data, allowMalformed: true);
    if (_buffer.contains('>')) {
      _dataController.add(_buffer);
      _buffer = '';
    }
  }

  @override
  Future<String> sendAndAwait(
    String command, {
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (!isConnected) throw Exception('غير متصل بمحول OBD2');
    final completer = Completer<String>();
    late StreamSubscription<String> sub;
    sub = _dataController.stream.listen((data) {
      if (!completer.isCompleted) {
        sub.cancel();
        completer.complete(data);
      }
    });

    _connection!.output.add(utf8.encode('$command\r'));
    await _connection!.output.allSent;

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        sub.cancel();
        return 'TIMEOUT';
      },
    );
  }

  @override
  Future<void> disconnect() async {
    _connection?.dispose();
    _connection = null;
  }

  void dispose() {
    disconnect();
    _dataController.close();
  }
}
