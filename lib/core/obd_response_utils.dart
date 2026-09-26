/// أدوات مشتركة لتحليل ردود ELM327 الخام — تُستخدم من Elm327Session فقط،
/// بدل تكرار نفس منطق التحليل في كل دالة قراءة PID كما كان سابقًا.
class ObdResponseUtils {
  static List<int> extractBytes(String raw) {
    final cleaned = raw
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('>', ' ')
        .trim();
    final parts =
        cleaned.split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final hexParts =
        parts.where((p) => RegExp(r'^[0-9A-Fa-f]{2}$').hasMatch(p)).toList();
    return hexParts.map((h) => int.parse(h, radix: 16)).toList();
  }

  static bool hasError(String raw) {
    final upper = raw.toUpperCase();
    return upper.contains('NO DATA') ||
        upper.contains('ERROR') ||
        upper.contains('UNABLE') ||
        upper.contains('TIMEOUT') ||
        upper.contains('DISCONNECTED') ||
        upper.contains('?');
  }
}
