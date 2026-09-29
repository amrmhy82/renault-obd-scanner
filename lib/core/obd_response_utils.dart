/// أدوات مشتركة لتحليل ردود ELM327 الخام — تُستخدم من Elm327Session فقط،
/// بدل تكرار نفس منطق التحليل في كل دالة قراءة PID كما كان سابقًا.
class ObdResponseUtils {
  /// يقبل الصيغتين: بايتات مفصولة بمسافات ("41 0C 1A F8") أو سلسلة متصلة
  /// بلا مسافات ("410C1AF8"). الصيغة الفعلية هنا هي الثانية دائمًا لأن
  /// initialize() يرسل ATS0 عمدًا (لتقليل حجم الردود عبر BLE) — وهذا بالضبط
  /// ما كان ناقصًا سابقًا: كانت الدالة تتجاهل أي كتلة أطول من حرفين فترجع
  /// قائمة فارغة لكل قراءة رغم وصول رد صحيح من السيارة.
  static List<int> extractBytes(String raw) {
    final cleaned = raw
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .replaceAll('>', ' ')
        .trim();
    final tokens = cleaned.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);

    final bytes = <int>[];
    for (final token in tokens) {
      // يتجاهل كلمات نصية مثل NO/DATA/SEARCHING (تحتوي حروفًا خارج A-F)
      if (!RegExp(r'^[0-9A-Fa-f]+$').hasMatch(token)) continue;
      final hex = token.length.isOdd ? token.substring(0, token.length - 1) : token;
      for (int i = 0; i + 2 <= hex.length; i += 2) {
        bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
    }
    return bytes;
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
