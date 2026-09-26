/// واجهة عامة لأي وسيلة اتصال بمحول OBD2 (بلوتوث كلاسيك، BLE، واي فاي، USB...).
/// أي طبقة أعلى (CommandQueue، Elm327Session) تتعامل مع هذه الواجهة فقط
/// ولا تعرف تفاصيل وسيلة النقل الفعلية، مما يسمح لاحقًا بإضافة أنواع اتصال
/// جديدة (مثلاً BluetoothLeTransport) دون تعديل أي كود آخر في التطبيق.
abstract class Transport {
  bool get isConnected;

  /// يحاول الاتصال، ويُرجع true عند النجاح
  Future<bool> connect();

  /// يقطع الاتصال ويحرر الموارد
  Future<void> disconnect();

  /// يرسل نصًا خامًا وينتظر حتى يصل رمز الموجه '>' (نهاية رد ELM327)،
  /// أو حتى انتهاء المهلة الزمنية (Timeout) فيُرجع النص 'TIMEOUT'.
  Future<String> sendAndAwait(
    String command, {
    Duration timeout = const Duration(seconds: 4),
  });
}
