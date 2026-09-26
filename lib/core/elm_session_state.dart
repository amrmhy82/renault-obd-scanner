/// دورة حياة صريحة لجلسة ELM327 تنعكس مباشرة على الواجهة، بدل رسالة
/// "متصل/غير متصل" الثنائية البسيطة فقط.
///
/// ملاحظة: `reconnecting` معرّفة هنا للمستقبل (منطق إعادة الاتصال الذكي
/// مؤجّل إلى P1)، وحاليًا الجلسة تنتقل فقط إلى `communicationError` دون
/// محاولة إعادة اتصال تلقائية بعد.
enum ElmSessionState {
  disconnected,
  connecting,
  initializing,
  detectingProtocol,
  ready,
  communicationError,
  reconnecting,
}
