import 'dart:async';
import 'transport.dart';

class ObdCommand {
  final String command;
  final Duration timeout;
  final int maxRetries;
  const ObdCommand(
    this.command, {
    this.timeout = const Duration(seconds: 3),
    this.maxRetries = 1,
  });
}

/// يضمن تنفيذ أمر واحد فقط في كل لحظة فوق اتصال تسلسلي واحد.
/// ملاحظة مهمة: لا يوجد "أولوية" حقيقية ممكنة هنا على مستوى الطابور نفسه،
/// لأن ELM327 يرد على أمر واحد بالمرة (طلب → رد → الطلب التالي) ولا يوجد
/// تعدد معالجة فعلي فوق منفذ تسلسلي واحد. الأولوية الفعلية تُطبَّق على
/// مستوى الجدولة (انظر LiveTelemetryService) عبر معدل تكرار القراءة، وليس
/// عبر إعادة ترتيب هذا الطابور. ما يضيفه الطابور هنا هو: منع تصادم أمرين
/// في نفس اللحظة + إعادة محاولة تلقائية عند التايم آوت أو الخطأ.
class CommandQueue {
  final Transport transport;
  CommandQueue(this.transport);

  Future<void>? _busy;

  Future<String> send(ObdCommand cmd) async {
    while (_busy != null) {
      try {
        await _busy;
      } catch (_) {}
    }
    final completer = Completer<void>();
    _busy = completer.future;
    try {
      String result = 'TIMEOUT';
      for (int attempt = 0; attempt <= cmd.maxRetries; attempt++) {
        if (!transport.isConnected) {
          result = 'DISCONNECTED';
          break;
        }
        result =
            await transport.sendAndAwait(cmd.command, timeout: cmd.timeout);
        final upper = result.toUpperCase();
        if (result != 'TIMEOUT' && !upper.contains('ERROR')) break;
      }
      return result;
    } finally {
      completer.complete();
      _busy = null;
    }
  }
}
