import 'package:permission_handler/permission_handler.dart';

/// نتيجة طلب صلاحيات البلوتوث، مع سبب الفشل لعرض رسالة مفيدة بدل خطأ خام.
class BtPermissionResult {
  final bool granted;

  /// true لو المستخدم رفضها نهائيًا ("عدم السؤال مجددًا") أو لو لم تُعلَن
  /// أصلًا في AndroidManifest (وفي الحالتين لن يظهر حوار طلب جديد).
  final bool needsSettingsOrManifest;

  const BtPermissionResult(this.granted, {this.needsSettingsOrManifest = false});
}

/// صلاحيات البلوتوث بعد فصلها حسب الغرض (بدل طلب الكل دفعة واحدة وتجاهل
/// النتيجة كما كان سابقًا):
///   - قراءة الأجهزة المقترنة/الاتصال  ← BLUETOOTH_CONNECT فقط
///   - البحث عن أجهزة قريبة            ← BLUETOOTH_SCAN + BLUETOOTH_CONNECT
///   - الموقع: يلزم فقط لأندرويد 11 وأقدم، ويُطلب بمحاولة اختيارية لا تمنع
///     المتابعة على أندرويد 12+ (حيث لا يلزم أصلًا).
///
/// ملاحظة: على أندرويد أقدم من 12 تُعامَل BLUETOOTH_SCAN/CONNECT كممنوحة
/// تلقائيًا. أما إن كانت الصلاحية غير معلنة في AndroidManifest.xml فسيرجع
/// الطلب "مرفوضًا" فورًا بلا أي حوار — لذلك نعرض للمستخدم رسالة تشرح ذلك.
class BluetoothPermissions {
  static bool _ok(PermissionStatus s) => s.isGranted || s.isLimited;

  /// للاتصال وقراءة الأجهزة المقترنة.
  static Future<BtPermissionResult> ensureConnect() async {
    final status = await Permission.bluetoothConnect.request();
    if (_ok(status)) return const BtPermissionResult(true);
    return BtPermissionResult(
      false,
      needsSettingsOrManifest: status.isPermanentlyDenied || status.isRestricted || status.isDenied,
    );
  }

  /// للبحث عن أجهزة قريبة (Classic أو BLE).
  static Future<BtPermissionResult> ensureScan() async {
    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    final allOk = statuses.values.every(_ok);
    if (!allOk) {
      return const BtPermissionResult(false, needsSettingsOrManifest: true);
    }
    // محاولة اختيارية للموقع (أندرويد 11 وأقدم يحتاجه للبحث) — لا نمنع
    // المتابعة إن رُفض، لأن أندرويد 12+ لا يحتاجه.
    try {
      if (!await Permission.locationWhenInUse.isGranted) {
        await Permission.locationWhenInUse.request();
      }
    } catch (_) {}
    return const BtPermissionResult(true);
  }

  static Future<void> openSettings() async {
    await openAppSettings();
  }

  static const String deniedMessage =
      'صلاحية البلوتوث غير ممنوحة للتطبيق.\n'
      '• لو ظهر لك حوار طلب الصلاحية سابقًا وضغطت "رفض": اضغط "فتح إعدادات التطبيق" '
      'ثم فعّل "الأجهزة القريبة" (Nearby devices).\n'
      '• لو لم يظهر أي حوار إطلاقًا: فـ AndroidManifest.xml ينقصه '
      'BLUETOOTH_CONNECT/BLUETOOTH_SCAN — شغّل الأمر `dart run tool/setup_android.dart` '
      'من جذر المشروع ثم أعد بناء التطبيق.';
}
