// يعدّل android/app/src/main/AndroidManifest.xml تلقائيًا:
//   1) يضيف xmlns:tools إن كان مفقودًا
//   2) يضيف صلاحيات البلوتوث الناقصة فقط (لا يكرر الموجود)
//   3) يضبط الاسم الظاهر تحت الأيقونة إلى "Matal Fluence Scan"
//   4) يرفع minSdk إلى 21 (مكتبة BLE تتطلبه، وقالب Flutter 3.19 يضع 19 فيفشل البناء)
//
// التشغيل (من جذر مشروع Flutter، بعد flutter create ونسخ الملفات):
//   dart run tool/setup_android.dart
//
// آمن للتشغيل أكثر من مرة (Idempotent)، وينشئ نسخة احتياطية AndroidManifest.xml.bak
// قبل أي تعديل. الهدف: إنهاء مشكلة "نسيت إضافة الصلاحيات يدويًا" نهائيًا.

import 'dart:io';

const String kManifestPath = 'android/app/src/main/AndroidManifest.xml';
const String kAppLabel = 'Matal Fluence Scan';

const Map<String, String> kPermissions = {
  'android.permission.BLUETOOTH':
      '<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />',
  'android.permission.BLUETOOTH_ADMIN':
      '<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />',
  'android.permission.BLUETOOTH_SCAN':
      '<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" tools:targetApi="s" />',
  'android.permission.BLUETOOTH_CONNECT':
      '<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />',
  'android.permission.ACCESS_FINE_LOCATION':
      '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />',
};

void main() {
  final file = File(kManifestPath);
  if (!file.existsSync()) {
    stderr.writeln('❌ لم أجد $kManifestPath');
    stderr.writeln('   شغّل الأمر من جذر مشروع Flutter (المجلد الذي فيه pubspec.yaml)،');
    stderr.writeln('   وتأكد أنك نفّذت flutter create قبل ذلك (هو الذي ينشئ مجلد android/).');
    exit(1);
  }

  final original = file.readAsStringSync();
  var xml = original;

  // 1) xmlns:tools
  if (!xml.contains('xmlns:tools=')) {
    xml = xml.replaceFirst(
      RegExp(r'<manifest\b'),
      '<manifest xmlns:tools="http://schemas.android.com/tools"',
    );
    stdout.writeln('➕ أُضيف xmlns:tools');
  }

  // 2) الصلاحيات الناقصة فقط
  final missing = <String>[];
  kPermissions.forEach((name, line) {
    if (!xml.contains('android:name="$name"')) {
      missing.add(line);
      stdout.writeln('➕ صلاحية ناقصة: $name');
    }
  });
  if (missing.isNotEmpty) {
    final block = missing.map((l) => '    $l').join('\n');
    xml = xml.replaceFirstMapped(
      RegExp(r'([ \t]*)<application\b'),
      (m) => '$block\n\n${m[1]}<application',
    );
  }

  // 3) الاسم الظاهر
  final labelRegex = RegExp(r'android:label="[^"]*"');
  if (labelRegex.hasMatch(xml)) {
    xml = xml.replaceFirstMapped(labelRegex, (m) => 'android:label="$kAppLabel"');
  } else {
    stdout.writeln('⚠️ لم أجد android:label في وسم application — عدّله يدويًا إن أردت.');
  }

  // 4) الحد الأدنى لإصدار أندرويد: flutter_blue_plus يتطلب 21 على الأقل، بينما
  //    قوالب Flutter القديمة (مثل 3.19) تضع flutter.minSdkVersion = 19.
  for (final path in ['android/app/build.gradle', 'android/app/build.gradle.kts']) {
    final g = File(path);
    if (!g.existsSync()) continue;
    final src = g.readAsStringSync();
    final re = RegExp(r'(minSdk(?:Version)?)(\s*=?\s*)(flutter\.minSdkVersion|\d+)');
    final patched = src.replaceAllMapped(re, (m) {
      final n = int.tryParse(m[3]!);
      if (n != null && n >= 21) return m[0]!; // مناسب أصلًا
      return '${m[1]}${m[2]}21';
    });
    if (patched != src) {
      File('$path.bak').writeAsStringSync(src);
      g.writeAsStringSync(patched);
      stdout.writeln('➕ رُفع minSdk إلى 21 في $path');
    } else {
      stdout.writeln('✔ minSdk في $path مناسب أصلًا');
    }
  }

  if (xml != original) {
    File('$kManifestPath.bak').writeAsStringSync(original);
    file.writeAsStringSync(xml);
    stdout.writeln('✅ تم تعديل $kManifestPath (نسخة احتياطية: $kManifestPath.bak)');
  } else {
    stdout.writeln('✅ لا تغييرات مطلوبة — الملف جاهز أصلًا.');
  }

  // تحقق نهائي
  final finalXml = file.readAsStringSync();
  var allOk = true;
  for (final name in kPermissions.keys) {
    final ok = finalXml.contains('android:name="$name"');
    if (!ok) allOk = false;
    stdout.writeln('${ok ? "✔" : "✘"} $name');
  }
  stdout.writeln('${finalXml.contains('android:label="$kAppLabel"') ? "✔" : "✘"} android:label = $kAppLabel');
  if (!allOk) {
    stderr.writeln('❌ بعض الصلاحيات ما أُضيفت. أرسل لي محتوى AndroidManifest.xml وأصلحه.');
    exit(2);
  }
  stdout.writeln('\nالخطوة التالية: flutter clean && flutter pub get && dart run flutter_launcher_icons && flutter build apk --release');
}
