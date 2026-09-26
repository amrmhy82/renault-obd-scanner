/// فئة الاستقصاء: تتحكم بعدد الدورات بين كل قراءة داخل LiveTelemetryService.
/// هذا هو المعنى العملي لـ"الأولوية" في تطبيقنا (وليس إعادة ترتيب طابور
/// الأوامر، غير الممكن فوق اتصال تسلسلي واحد — راجع تعليق CommandQueue).
enum PollClass { fast, medium, slow }

/// تصنيف PID لعرضه في مجموعات منفصلة بلوحة البيانات، مع الحفاظ على أن
/// PidRegistry هو المصدر الوحيد للحقيقة (Single Source of Truth).
enum PidCategory { basics, combustion }

class PidDefinition {
  final String key;
  final String nameAr;
  final String unit;
  final String command; // مثل '010C'
  final PollClass pollClass;
  final PidCategory category;

  /// bytes هنا هي كل البايتات المستخرجة من الرد (تشمل 41 ورقم الـ PID نفسه)
  final num? Function(List<int> bytes) parse;

  const PidDefinition({
    required this.key,
    required this.nameAr,
    required this.unit,
    required this.command,
    required this.pollClass,
    this.category = PidCategory.basics,
    required this.parse,
  });
}

/// سجل موحّد لكل PIDs المدعومة. إضافة قياس جديد تكون بإضافة عنصر واحد هنا
/// فقط، بدل تكرار منطق الإرسال والتحليل في كل شاشة كما كان سابقًا.
///
/// كل صيغ التحليل أدناه (بما فيها حساسات الاحتراق) مطابقة لمعيار
/// SAE J1979 القياسي، وتم التحقق منها رياضيًا قبل الإضافة.
class PidRegistry {
  static final List<PidDefinition> all = [
    // ═══════════════════════ الأساسيات (Basics) ═══════════════════════
    PidDefinition(
      key: 'rpm',
      nameAr: 'دورات المحرك',
      unit: 'RPM',
      command: '010C',
      pollClass: PollClass.fast,
      parse: (b) => b.length >= 4 ? ((b[2] * 256) + b[3]) ~/ 4 : null,
    ),
    PidDefinition(
      key: 'speed',
      nameAr: 'السرعة',
      unit: 'كم/س',
      command: '010D',
      pollClass: PollClass.fast,
      parse: (b) => b.length >= 3 ? b[2] : null,
    ),
    PidDefinition(
      key: 'engine_load',
      nameAr: 'حمل المحرك المحسوب',
      unit: '%',
      command: '0104',
      pollClass: PollClass.fast,
      parse: (b) => b.length >= 3 ? b[2] * 100 / 255 : null,
    ),
    PidDefinition(
      key: 'throttle',
      nameAr: 'وضع دواسة البنزين',
      unit: '%',
      command: '0111',
      pollClass: PollClass.fast,
      parse: (b) => b.length >= 3 ? b[2] * 100 / 255 : null,
    ),
    PidDefinition(
      key: 'absolute_load',
      nameAr: 'الحمل المطلق للمحرك',
      unit: '%',
      command: '0143',
      pollClass: PollClass.medium,
      parse: (b) => b.length >= 4 ? ((b[2] * 256) + b[3]) * 100 / 255 : null,
    ),
    PidDefinition(
      key: 'coolant_temp',
      nameAr: 'حرارة سائل التبريد',
      unit: '°م',
      command: '0105',
      pollClass: PollClass.medium,
      parse: (b) => b.length >= 3 ? b[2] - 40 : null,
    ),
    PidDefinition(
      key: 'map',
      nameAr: 'ضغط مشعب السحب (MAP)',
      unit: 'kPa',
      command: '010B',
      pollClass: PollClass.medium,
      parse: (b) => b.length >= 3 ? b[2] : null,
    ),
    PidDefinition(
      key: 'iat',
      nameAr: 'حرارة هواء السحب',
      unit: '°م',
      command: '010F',
      pollClass: PollClass.medium,
      parse: (b) => b.length >= 3 ? b[2] - 40 : null,
    ),
    PidDefinition(
      key: 'battery_voltage',
      nameAr: 'جهد نظام الكهرباء',
      unit: 'V',
      command: '0142',
      pollClass: PollClass.medium,
      parse: (b) => b.length >= 4 ? ((b[2] * 256) + b[3]) / 1000 : null,
    ),
    PidDefinition(
      key: 'fuel_level',
      nameAr: 'مستوى الوقود',
      unit: '%',
      command: '012F',
      pollClass: PollClass.slow,
      parse: (b) => b.length >= 3 ? b[2] * 100 / 255 : null,
    ),

    // ═══════════════════ الاحتراق المتقدم (Combustion) ═══════════════════
    // كل هذه قياسية (Mode 01) ومضمّنة في SAE J1979، يُفترض أن يعرضها أي
    // محرك بنزين حديث يدعم EOBD. ظهور "--" لأي قيمة بعد اتصال كافٍ يعني أن
    // وحدة الحقن تحديدًا لا تُبلّغ عن هذا PID (يختلف بين نسخ برنامج
    // المحرك)، وليس خللًا بالتطبيق — راجع شاشة "سجل التصحيح (Debug)".
    PidDefinition(
      key: 'stft_b1',
      nameAr: 'تعديل الوقود قصير المدى (بنك 1)',
      unit: '%',
      command: '0106',
      pollClass: PollClass.medium,
      category: PidCategory.combustion,
      parse: (b) => b.length >= 3 ? (b[2] - 128) * 100 / 128 : null,
    ),
    PidDefinition(
      key: 'ltft_b1',
      nameAr: 'تعديل الوقود طويل المدى (بنك 1)',
      unit: '%',
      command: '0107',
      pollClass: PollClass.slow,
      category: PidCategory.combustion,
      parse: (b) => b.length >= 3 ? (b[2] - 128) * 100 / 128 : null,
    ),
    PidDefinition(
      key: 'o2_b1s1',
      nameAr: 'حساس الأكسجين الأمامي (بنك 1 - حساس 1)',
      unit: 'V',
      command: '0114',
      pollClass: PollClass.medium,
      category: PidCategory.combustion,
      parse: (b) => b.length >= 4 ? b[2] / 200 : null,
    ),
    PidDefinition(
      key: 'o2_b1s2',
      nameAr: 'حساس الأكسجين الخلفي (بنك 1 - حساس 2)',
      unit: 'V',
      command: '0115',
      pollClass: PollClass.medium,
      category: PidCategory.combustion,
      parse: (b) => b.length >= 4 ? b[2] / 200 : null,
    ),
    PidDefinition(
      key: 'timing_advance',
      nameAr: 'تقديم توقيت الإشعال',
      unit: '°',
      command: '010E',
      pollClass: PollClass.medium,
      category: PidCategory.combustion,
      parse: (b) => b.length >= 3 ? (b[2] / 2) - 64 : null,
    ),
    PidDefinition(
      key: 'cmd_throttle',
      nameAr: 'وضعية الخانق المطلوبة من ECU',
      unit: '%',
      command: '014C',
      pollClass: PollClass.medium,
      category: PidCategory.combustion,
      parse: (b) => b.length >= 3 ? b[2] * 100 / 255 : null,
    ),
    PidDefinition(
      key: 'equiv_ratio',
      nameAr: 'نسبة التكافؤ (Lambda)',
      unit: 'λ',
      command: '0144',
      pollClass: PollClass.medium,
      category: PidCategory.combustion,
      parse: (b) => b.length >= 4 ? ((b[2] * 256) + b[3]) / 32768 : null,
    ),
    PidDefinition(
      key: 'fuel_rail_rel',
      nameAr: 'ضغط قضيب الوقود (نسبي)',
      unit: 'kPa',
      command: '0122',
      pollClass: PollClass.slow,
      category: PidCategory.combustion,
      parse: (b) => b.length >= 4 ? ((b[2] * 256) + b[3]) * 0.079 : null,
    ),
  ];

  static PidDefinition byKey(String key) => all.firstWhere((p) => p.key == key);

  /// ترجع كل PIDs المنتمية لتصنيف معيّن مع الحفاظ على ترتيب التعريف أعلاه.
  static List<PidDefinition> byCategory(PidCategory c) =>
      all.where((p) => p.category == c).toList();
}
