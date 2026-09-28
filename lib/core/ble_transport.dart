import 'dart:async';
import 'dart:convert';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'transport.dart';

/// تنفيذ [Transport] عبر **BLE (Bluetooth Low Energy)** لمحولات ELM327 الحديثة
/// الصغيرة. الفرق الجوهري عن الكلاسيك: لا يوجد "إقران" ولا منفذ تسلسلي (SPP)،
/// بل خدمة GATT فيها خاصية للإشعارات (نستقبل منها الردود) وخاصية للكتابة
/// (نرسل إليها الأوامر). أغلب هذه المحولات تستخدم أحد نمطين:
///   - خدمة FFF0: خاصية FFF1 (إشعارات) + FFF2 (كتابة)
///   - خدمة FFE0: خاصية FFE1 واحدة للاثنين
/// لكن بدل الاعتماد على UUID محدد نكتشف الخصائص ديناميكيًا حسب خصائصها
/// (notify/write) فيعمل مع معظم الموديلات دون تخصيص لكل واحد.
///
/// المنطق الأعلى (CommandQueue/Elm327Session) لا يعرف شيئًا عن هذا الفرق —
/// نفس أوامر AT ونفس تحليل الردود، لأن البروتوكول فوق النقل واحد.
class BleTransport implements Transport {
  final BluetoothDevice device;
  BleTransport(this.device);

  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  StreamSubscription<List<int>>? _notifySub;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  final StreamController<String> _dataController =
      StreamController<String>.broadcast();
  String _buffer = '';
  bool _connected = false;

  /// آخر سبب فشل (للعرض في الشاشة وللتشخيص) — يشمل قائمة الخدمات المكتشفة
  /// لو لم نجد خصائص مناسبة، فنعرف بالضبط ما يعرضه المحول.
  String? lastError;

  @override
  bool get isConnected => _connected;

  @override
  Future<bool> connect() async {
    lastError = null;
    try {
      await _cleanup(); // يسمح بإعادة الاتصال على نفس الكائن
      await device.connect(timeout: const Duration(seconds: 15));

      _connSub = device.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected) _connected = false;
      });

      final services = await device.discoverServices();
      if (!_pickCharacteristics(services)) {
        await _safeDisconnect();
        return false;
      }

      await _notifyChar!.setNotifyValue(true);
      _notifySub = _notifyChar!.onValueReceived.listen(_onData);
      _connected = true;
      return true;
    } catch (e) {
      lastError = 'استثناء أثناء الاتصال: $e';
      _connected = false;
      await _safeDisconnect();
      return false;
    }
  }

  bool _isGenericService(BluetoothService s) {
    final u = s.uuid.str128.toLowerCase();
    // GAP / GATT / Device Information — ليست قناة بيانات المحول
    return u.startsWith('00001800') || u.startsWith('00001801') || u.startsWith('0000180a');
  }

  bool _canNotify(BluetoothCharacteristic c) =>
      c.properties.notify || c.properties.indicate;

  bool _canWrite(BluetoothCharacteristic c) =>
      c.properties.write || c.properties.writeWithoutResponse;

  bool _pickCharacteristics(List<BluetoothService> services) {
    BluetoothCharacteristic? notify;
    BluetoothCharacteristic? write;

    // 1) أفضل حالة: خدمة واحدة فيها خاصية إشعارات وخاصية كتابة (قد تكونان
    //    نفس الخاصية كما في نمط FFE1).
    for (final s in services) {
      if (_isGenericService(s)) continue;
      BluetoothCharacteristic? n;
      BluetoothCharacteristic? w;
      for (final c in s.characteristics) {
        if (n == null && _canNotify(c)) n = c;
        if (w == null && _canWrite(c)) w = c;
      }
      if (n != null && w != null) {
        notify = n;
        write = w;
        break;
      }
    }

    // 2) احتياط: أي إشعارات وأي كتابة من خدمات مختلفة
    if (notify == null || write == null) {
      for (final s in services) {
        if (_isGenericService(s)) continue;
        for (final c in s.characteristics) {
          notify ??= _canNotify(c) ? c : null;
          write ??= _canWrite(c) ? c : null;
        }
      }
    }

    if (notify == null || write == null) {
      final dump = services
          .map((s) =>
              '${s.uuid.str}: [${s.characteristics.map((c) => '${c.uuid.str}(${_props(c)})').join(', ')}]')
          .join(' | ');
      lastError = 'لم أجد خاصية إشعارات + كتابة مناسبة. الخدمات المكتشفة: $dump';
      return false;
    }
    _notifyChar = notify;
    _writeChar = write;
    return true;
  }

  String _props(BluetoothCharacteristic c) {
    final p = c.properties;
    final out = <String>[];
    if (p.read) out.add('R');
    if (p.write) out.add('W');
    if (p.writeWithoutResponse) out.add('WNR');
    if (p.notify) out.add('N');
    if (p.indicate) out.add('I');
    return out.join('');
  }

  void _onData(List<int> data) {
    _buffer += utf8.decode(data, allowMalformed: true);
    // نهاية رد ELM327 هي رمز الموجه '>' — والرد قد يصل مقسومًا على عدة
    // حزم (حجم الحزمة في BLE صغير غالبًا 20 بايت).
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
    final w = _writeChar;
    if (!isConnected || w == null) throw Exception('غير متصل بمحول OBD2');

    final completer = Completer<String>();
    late StreamSubscription<String> sub;
    sub = _dataController.stream.listen((data) {
      if (!completer.isCompleted) {
        sub.cancel();
        completer.complete(data);
      }
    });

    _buffer = ''; // تجاهل أي بقايا رد قديم غير مكتمل
    try {
      final bytes = utf8.encode('$command\r');
      final noResponse = w.properties.writeWithoutResponse;
      // نقسّم على حزم 20 بايت (الحد الأدنى المضمون بدون تفاوض MTU)
      for (int i = 0; i < bytes.length; i += 20) {
        final end = (i + 20 < bytes.length) ? i + 20 : bytes.length;
        await w.write(bytes.sublist(i, end), withoutResponse: noResponse);
      }
    } catch (e) {
      sub.cancel();
      lastError = 'فشل الكتابة: $e';
      return 'BLE WRITE ERROR';
    }

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        sub.cancel();
        return 'TIMEOUT';
      },
    );
  }

  Future<void> _cleanup() async {
    await _notifySub?.cancel();
    _notifySub = null;
    await _connSub?.cancel();
    _connSub = null;
    _buffer = '';
    _connected = false;
  }

  Future<void> _safeDisconnect() async {
    try {
      await device.disconnect();
    } catch (_) {}
  }

  @override
  Future<void> disconnect() async {
    await _cleanup();
    await _safeDisconnect();
  }

  void dispose() {
    disconnect();
    _dataController.close();
  }
}
