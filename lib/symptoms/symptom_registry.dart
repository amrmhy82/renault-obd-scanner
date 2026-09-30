import 'symptom_models.dart';

class SymptomRegistry {
  static const all = <SymptomDefinition>[
    SymptomDefinition(
      id: 'S001', nameAr: 'اهتزاز عند الوقوف', descriptionAr: 'تذبذب أو رجفة والمحرك يعمل دون حركة',
      category: SymptomCategory.engine, severity: SymptomSeverity.medium,
      relatedDtcs: ['P0300', 'P0301', 'P0302', 'P0303', 'P0304', 'P0171'],
      requiredPids: ['rpm', 'coolant_temp', 'map', 'stft_b1', 'ltft_b1', 'o2_b1s1', 'o2_b1s2'],
      recommendations: ['فحص البوجيهات والكويلات عند وجود دليل Misfire', 'فحص تسريب هواء السحب', 'مراجعة أكواد الأعطال الحالية والمعلّقة'],
      idleSeconds: 60, loadSeconds: 30,
    ),
    SymptomDefinition(id: 'S002', nameAr: 'ضعف التسارع', descriptionAr: 'استجابة ضعيفة عند الضغط على دواسة الوقود', category: SymptomCategory.engine, severity: SymptomSeverity.medium, requiredPids: ['rpm', 'speed', 'engine_load', 'throttle', 'map', 'stft_b1', 'ltft_b1'], idleSeconds: 30, loadSeconds: 60),
    SymptomDefinition(id: 'S003', nameAr: 'تقطيع عند البداية', descriptionAr: 'تقطيع أو تردد عند بدء الحركة', category: SymptomCategory.engine, severity: SymptomSeverity.high, relatedDtcs: ['P0300', 'P0301', 'P0302', 'P0303', 'P0304'], requiredPids: ['rpm', 'coolant_temp', 'stft_b1', 'ltft_b1', 'o2_b1s1']),
    SymptomDefinition(id: 'S004', nameAr: 'ارتفاع حرارة المحرك', descriptionAr: 'ارتفاع غير معتاد في حرارة المحرك', category: SymptomCategory.cooling, severity: SymptomSeverity.high, requiredPids: ['coolant_temp', 'rpm', 'speed'], recommendations: ['تجنب مواصلة القيادة عند ارتفاع الحرارة', 'فحص مستوى سائل التبريد ودورة التبريد'],),
    SymptomDefinition(id: 'S005', nameAr: 'استهلاك وقود مرتفع', descriptionAr: 'زيادة ملحوظة في استهلاك الوقود', category: SymptomCategory.fuel, severity: SymptomSeverity.medium, requiredPids: ['rpm', 'engine_load', 'stft_b1', 'ltft_b1', 'o2_b1s1', 'fuel_level']),
    SymptomDefinition(id: 'S006', nameAr: 'لمبة المحرك مضيئة', descriptionAr: 'ظهور لمبة فحص المحرك', category: SymptomCategory.general, severity: SymptomSeverity.high, relatedDtcs: ['P0300', 'P0171', 'P0420'], requiredPids: ['rpm', 'coolant_temp', 'engine_load']),
    SymptomDefinition(id: 'S007', nameAr: 'صعوبة التشغيل البارد', descriptionAr: 'صعوبة تشغيل المحرك عند البرودة', category: SymptomCategory.engine, severity: SymptomSeverity.medium, requiredPids: ['coolant_temp', 'iat', 'battery_voltage', 'stft_b1', 'ltft_b1']),
    SymptomDefinition(id: 'S008', nameAr: 'رائحة وقود', descriptionAr: 'وجود رائحة وقود غير معتادة', category: SymptomCategory.fuel, severity: SymptomSeverity.high, requiredPids: ['stft_b1', 'ltft_b1', 'o2_b1s1', 'o2_b1s2'], recommendations: ['افحص أي تسريب وقود فورًا قبل مواصلة القيادة'],),
    SymptomDefinition(id: 'S009', nameAr: 'مشكلة كهربائية ظاهرة', descriptionAr: 'أعراض مرتبطة بجهد النظام أو البطارية', category: SymptomCategory.electrical, severity: SymptomSeverity.medium, requiredPids: ['battery_voltage', 'rpm']),
    SymptomDefinition(id: 'S010', nameAr: 'نتشة أو تأخر تعشيق', descriptionAr: 'عرض مرتبط بناقل الحركة ويحتاج فحصًا متخصصًا', category: SymptomCategory.transmission, severity: SymptomSeverity.high, recommendations: ['هذه النسخة لا تشخّص CVT؛ يلزم فحص متخصص وبيانات وحدة الناقل'],),
  ];

  static SymptomDefinition byId(String id) => all.firstWhere((s) => s.id == id);
}
