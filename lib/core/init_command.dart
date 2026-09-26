/// أمر تهيئة واحد (AT command) مع دالة تحقق خاصة به، بدل افتراض أن كل رد
/// "ناجح" طالما لا يحتوي كلمة خطأ. أوامر مختلفة لها أنماط رد مختلفة
/// (`ATZ` يرد بنص تعريفي طويل، بينما البقية غالبًا يكفيها عدم وجود خطأ).
class InitCommand {
  final String command;
  final Duration timeout;
  final bool Function(String rawResponse) isSuccess;

  const InitCommand(
    this.command, {
    this.timeout = const Duration(seconds: 3),
    required this.isSuccess,
  });
}
