import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

/// مصدر كود DTC — يفرّق بين الأكواد القياسية SAE وأكواد الشركة المصنّعة،
/// لأن المعنى والإجراء التشخيصي يختلفان جذريًا بينهما.
///
/// ملاحظة مهمة: هذا التصنيف مبني فقط على **شكل الكود** (بادئته وطوله) وفق
/// معيار SAE J2012 العام، وليس على معرفة معنى كود رينو الخاص تحديدًا. لا
/// نملك حاليًا قاعدة بيانات موثوقة لمعاني أكواد رينو المصنّعية (DFxxx)، لأن
/// هذه غير موحّدة علنًا وموثّقة فقط داخل أدوات صيانة رسمية (مثل DDT4All)
/// نحتاج التحقق منها ميدانيًا أولًا قبل عرضها كحقيقة.
enum DtcSource {
  /// [PCBU]0xxx و[PCBU]2xxx و[PCBU]3xxx — قياسي مشترك بين كل الشركات
  saeStandard,

  /// [PCBU]1xxx — بتنسيق SAE لكن المعنى خاص بكل شركة
  saeManufacturer,

  /// تنسيق غير SAE قياسي (مثل DFxxx التي تستخدمها أدوات رينو الخاصة عبر
  /// UDS Mode 19) — نُصنّفه فقط، ولا ندّعي معرفة معناه الدقيق
  nonStandardFormat,

  unknown,
}

/// قاعدة بيانات محلية لتفسير أكواد DTC. تحوي أكواد SAE القياسية الشائعة
/// (~110 كود) موثّقة يدويًا، مع رد احتياطي ذكي حسب شكل أي كود آخر — بدون
/// افتراض معرفة أكواد مصنّعية لم نتحقق منها.
class DtcDatabase {
  Map<String, String> _codes = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString('assets/dtc_codes_ar.json');
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _codes = map.map((k, v) => MapEntry(k, v as String));
    } catch (_) {
      _codes = {};
    } finally {
      _loaded = true;
    }
  }

  /// إرجاع وصف عربي للكود إن وُجد في القاعدة الموثَّقة، وإلا وصف عام حسب فئته
  String describe(String code) {
    final exact = _codes[code.toUpperCase()];
    if (exact != null) return exact;
    return _genericFallback(code);
  }

  /// تصنيف الكود حسب بادئته وشكله فقط — بلا اعتماد على قاعدة البيانات ولا
  /// افتراض معرفة المعنى الدقيق لأكواد الشركة المصنّعة.
  DtcSource sourceOf(String code) {
    final c = code.trim().toUpperCase();
    if (c.isEmpty) return DtcSource.unknown;

    // تنسيق SAE القياسي: [PCBU][0-3][0-9A-F]{3}
    if (c.length == 5 && 'PCBU'.contains(c[0])) {
      final second = c[1];
      if (second == '0' || second == '2' || second == '3') {
        return DtcSource.saeStandard;
      }
      if (second == '1') return DtcSource.saeManufacturer;
    }

    // أي تنسيق آخر غير مطابق لبنية SAE القياسية (مثل DFxxx) — نصنّفه فقط
    // كـ"غير قياسي" دون ادّعاء معرفة معناه.
    if (RegExp(r'^[A-Z]{1,3}[0-9A-Z]{3,6}$').hasMatch(c)) {
      return DtcSource.nonStandardFormat;
    }
    return DtcSource.unknown;
  }

  /// نص عربي قصير لشارة المصدر في الواجهة.
  String sourceLabelAr(DtcSource s) {
    switch (s) {
      case DtcSource.saeStandard:
        return 'قياسي SAE';
      case DtcSource.saeManufacturer:
        return 'شركة (تنسيق SAE)';
      case DtcSource.nonStandardFormat:
        return 'تنسيق غير قياسي';
      case DtcSource.unknown:
        return 'غير مصنّف';
    }
  }

  String _genericFallback(String code) {
    if (code.isEmpty) return 'كود غير معروف';

    final src = sourceOf(code);
    final prefix = code[0].toUpperCase();

    String category;
    switch (prefix) {
      case 'P':
        category = 'نظام الدفع (المحرك / ناقل الحركة)';
        break;
      case 'C':
        category = 'نظام الهيكل (التعليق / الفرامل / التوجيه)';
        break;
      case 'B':
        category = 'جسم السيارة (الوسائد الهوائية / المناخ / الإضاءة)';
        break;
      case 'U':
        category = 'شبكة الاتصال بين وحدات التحكم';
        break;
      default:
        category = 'غير معروفة';
    }

    String origin;
    switch (src) {
      case DtcSource.saeStandard:
        origin = 'كود قياسي عام (SAE J1979) مشترك بين كل الشركات.';
        break;
      case DtcSource.saeManufacturer:
        origin = 'كود بتنسيق SAE لكن معناه خاص بالشركة المصنّعة (رينو على الأرجح).';
        break;
      case DtcSource.nonStandardFormat:
        origin = 'تنسيق غير قياسي (على الأرجح كود خاص بأداة تشخيص المصنّع، '
            'مثل DFxxx التي تستخدمها أدوات رينو عبر UDS Mode 19 — غير مدعوم '
            'حاليًا في هذا التطبيق). لا نملك معنى موثّقًا لهذا الكود تحديدًا.';
        break;
      case DtcSource.unknown:
        origin = 'تنسيق الكود غير معروف.';
    }

    return 'لا يوجد وصف تفصيلي محفوظ لهذا الكود محليًا. '
        'هو من فئة: $category — $origin '
        'ابحث عن "$code" في موقع OBD-Codes.com لمعرفة وصفه وأسبابه بدقة.';
  }
}
