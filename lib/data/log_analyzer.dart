import 'dart:io';
import 'dart:math' as math;
import '../core/pid_registry.dart';
import '../health/health_finding.dart';

/// عينة واحدة من ملف CSV (صف واحد).
class LogSample {
  final DateTime timestamp;
  final int elapsedMs;
  final Map<String, num?> values;

  const LogSample({
    required this.timestamp,
    required this.elapsedMs,
    required this.values,
  });
}

/// نتيجة قراءة ملف CSV كامل: أسماء الأعمدة + كل العينات.
class ParsedLog {
  final List<String> columns; // ['timestamp_iso', 'elapsed_ms', 'rpm', ...]
  final List<LogSample> samples;

  const ParsedLog({required this.columns, required this.samples});

  bool get isEmpty => samples.isEmpty;
  List<String> get pidKeys => columns.length > 2 ? columns.sublist(2) : const [];
}

/// إحصاءات عمود واحد عبر جلسة التسجيل.
class ColumnStats {
  final String key;
  final int validCount;
  final num? min;
  final num? max;
  final double? mean;
  final double? stdDev;
  final double? median;

  const ColumnStats({
    required this.key,
    required this.validCount,
    required this.min,
    required this.max,
    required this.mean,
    required this.stdDev,
    required this.median,
  });

  bool get hasData => validCount > 0;
}

/// تقرير التحليل الكامل لجلسة تسجيل.
class LogAnalysisReport {
  final int rowCount;
  final Duration duration;
  final double samplingHz;
  final DateTime? sessionStart;
  final List<HealthFinding> findings;
  final Map<String, ColumnStats> stats;
  final List<String> missingSensorKeys;

  const LogAnalysisReport({
    required this.rowCount,
    required this.duration,
    required this.samplingHz,
    required this.sessionStart,
    required this.findings,
    required this.stats,
    required this.missingSensorKeys,
  });

  bool get hasFindings => findings.isNotEmpty;
}

/// محلّل خالص: يأخذ ملف CSV، يُرجع تقريرًا. لا UI، لا حالة، قابل للاختبار
/// بمعزل تام عن أي واجهة.
///
/// كل القواعد أدناه مبنية على نطاقات تشغيلية عامة موثّقة في مصادر تشخيص
/// OBD2 قياسية، وليست قيمًا اعتباطية — لكنها **عتبات تقريبية أولية** وليست
/// مُعايرة خصيصًا لمحرك رينو فلوانس K4M. كل الثوابت مجمّعة أعلى الكلاس
/// لتسهيل تعديلها لاحقًا بعد جمع بيانات فعلية كافية من هذه السيارة تحديدًا.
class LogAnalyzer {
  // حد حجم الملف: نحمّل الملف كاملًا في الذاكرة، لذا 20MB سقف آمن.
  static const int _maxFileSizeBytes = 20 * 1024 * 1024;

  // ─── عتبات قواعد الحرارة ───
  static const num coolantCriticalC = 108;
  static const num coolantHighC = 100;
  static const num coolantLowThermostatC = 75;
  static const int thermostatMinSessionSec = 300; // 5 دقائق

  // ─── عتبات قواعد الكهرباء ───
  static const num batteryLowV = 11.8;
  static const num chargingMinV = 13.2;
  static const num chargingMinRpm = 500;

  // ─── عتبات قواعد الاحتراق ───
  static const double stftWildStdDev = 12.0;
  static const double ltftLeanThreshold = 10.0;
  static const double ltftRichThreshold = -10.0;
  static const double o2FrontStuckStdDev = 0.05;
  static const double o2RearOscillatingStdDev = 0.25;
  static const num o2DetectionMinRpm = 1000;

  // ─── عتبات عامة ───
  static const int shortSessionSec = 60;

  /// يقرأ ملف CSV ويُرجع ParsedLog، أو null عند فشل القراءة (ملف تالف/ضخم).
  static Future<ParsedLog?> parseCsv(File file) async {
    try {
      final stat = await file.stat();
      if (stat.size > _maxFileSizeBytes) return null;

      final lines = await file.readAsLines();
      if (lines.isEmpty) return null;

      // إزالة BOM إن وُجد (نكتبه نحن في DataLoggerService)
      var header = lines.first;
      if (header.isNotEmpty && header.codeUnitAt(0) == 0xFEFF) {
        header = header.substring(1);
      }
      final cols = header.split(',');
      if (cols.length < 3) return null;

      final samples = <LogSample>[];
      for (int i = 1; i < lines.length; i++) {
        final line = lines[i];
        if (line.trim().isEmpty) continue;
        final parts = line.split(',');
        if (parts.length < 2) continue;

        final ts = DateTime.tryParse(parts[0]);
        final elapsed = int.tryParse(parts[1]);
        if (ts == null || elapsed == null) continue;

        final values = <String, num?>{};
        for (int c = 2; c < cols.length && c < parts.length; c++) {
          final raw = parts[c].trim();
          values[cols[c]] = raw.isEmpty ? null : num.tryParse(raw);
        }
        samples.add(LogSample(timestamp: ts, elapsedMs: elapsed, values: values));
      }
      return ParsedLog(columns: cols, samples: samples);
    } catch (_) {
      return null;
    }
  }

  /// التحليل الفعلي — دالة خالصة.
  static LogAnalysisReport analyze(ParsedLog parsed) {
    if (parsed.isEmpty) {
      return const LogAnalysisReport(
        rowCount: 0,
        duration: Duration.zero,
        samplingHz: 0,
        sessionStart: null,
        findings: [],
        stats: {},
        missingSensorKeys: [],
      );
    }

    final samples = parsed.samples;
    final start = samples.first.timestamp;
    final end = samples.last.timestamp;
    final duration = end.difference(start);
    final sec = duration.inMilliseconds / 1000.0;
    final hz = sec > 0 ? samples.length / sec : 0.0;

    // إحصاءات كل عمود + كشف الأعمدة الفارغة تمامًا
    final stats = <String, ColumnStats>{};
    final missing = <String>[];
    for (final key in parsed.pidKeys) {
      final vals = _numericValues(samples, key);
      stats[key] = _computeStats(key, vals);
      if (vals.isEmpty) missing.add(key);
    }

    final findings = <HealthFinding>[];

    // ═══════════════════════ قواعد الحرارة ═══════════════════════
    final coolant = stats['coolant_temp'];
    if (coolant != null && coolant.hasData) {
      if (coolant.max! >= coolantCriticalC) {
        findings.add(HealthFinding(
          title: 'ارتفاع خطير في حرارة التبريد',
          explanation: 'بلغت ذروة الحرارة ${coolant.max}°م أثناء الجلسة، '
              'وهي أعلى من الحد الآمن (${coolantCriticalC}°م).',
          recommendation:
              'تحقق من مستوى سائل التبريد، عمل المروحة، والثرموستات. القيادة بهذه الحرارة تضر المحرك.',
          severity: HealthSeverity.critical,
          scoreImpact: -25,
        ));
      } else if (coolant.max! >= coolantHighC) {
        findings.add(HealthFinding(
          title: 'حرارة تبريد أعلى من المعتاد',
          explanation: 'بلغت ذروة الحرارة ${coolant.max}°م، '
              'أعلى من النطاق الطبيعي التقريبي (~85–95°م) لكن دون حد الخطر.',
          recommendation: 'راقب المؤشر. إذا تكرر الارتفاع فافحص المروحة ومستوى السائل.',
          severity: HealthSeverity.warning,
          scoreImpact: -10,
        ));
      }
      if (sec >= thermostatMinSessionSec && coolant.max! < coolantLowThermostatC) {
        findings.add(HealthFinding(
          title: 'المحرك لا يصل لحرارة التشغيل الطبيعية',
          explanation: 'بعد ${(sec / 60).toStringAsFixed(1)} دقيقة، '
              'ذروة الحرارة ${coolant.max}°م فقط — أقل من المتوقع.',
          recommendation: 'احتمال ثرموستات مفتوح باستمرار. فحصه يوفر وقودًا ويُحسّن الأداء.',
          severity: HealthSeverity.warning,
          scoreImpact: -10,
        ));
      }
    }

    // ═══════════════════════ قواعد الكهرباء ═══════════════════════
    final batt = stats['battery_voltage'];
    final rpm = stats['rpm'];
    if (batt != null && batt.hasData) {
      if (batt.min! < batteryLowV) {
        findings.add(HealthFinding(
          title: 'جهد بطارية منخفض أثناء الجلسة',
          explanation: 'أدنى جهد ${batt.min!.toStringAsFixed(2)} فولت، '
              'وهو أقل من الحد الطبيعي التقريبي ($batteryLowV فولت).',
          recommendation: 'افحص البطارية والدينمو. قد تحتاج شحنًا أو استبدالًا.',
          severity: HealthSeverity.warning,
          scoreImpact: -15,
        ));
      }
      if (rpm != null && rpm.hasData && rpm.median != null && rpm.median! > chargingMinRpm) {
        final chargingSamples = samples.where((s) {
          final v = s.values['battery_voltage'];
          final r = s.values['rpm'];
          return v != null && r != null && r > chargingMinRpm && v < chargingMinV;
        }).length;
        final ratio = chargingSamples / samples.length;
        if (ratio > 0.3) {
          findings.add(HealthFinding(
            title: 'شحن ضعيف من الدينمو',
            explanation: 'في ${(ratio * 100).round()}% من الوقت أثناء دوران المحرك، '
                'كان الجهد أقل من $chargingMinV فولت (المتوسط ${batt.mean!.toStringAsFixed(2)}).',
            recommendation: 'افحص الدينمو وسير المروحة وتوصيلات الأرضي.',
            severity: HealthSeverity.warning,
            scoreImpact: -20,
          ));
        }
      }
    }

    // ═══════════════════════ قواعد الاحتراق ═══════════════════════
    final stft = stats['stft_b1'];
    if (stft != null && stft.hasData && stft.stdDev != null) {
      if (stft.stdDev! >= stftWildStdDev) {
        findings.add(HealthFinding(
          title: 'تذبذب غير طبيعي في تعديل الوقود قصير المدى',
          explanation: 'الانحراف المعياري لـ STFT هو ${stft.stdDev!.toStringAsFixed(1)}% '
              '(النطاق: ${stft.min!.toStringAsFixed(0)}% إلى ${stft.max!.toStringAsFixed(0)}%).',
          recommendation:
              'احتمال تسرب فراغي، حساس MAF متسخ، أو ضغط وقود غير مستقر. فحص الدخان/الهواء مفيد.',
          severity: HealthSeverity.warning,
          scoreImpact: -15,
        ));
      }
    }

    final ltft = stats['ltft_b1'];
    if (ltft != null && ltft.hasData && ltft.mean != null) {
      if (ltft.mean! > ltftLeanThreshold) {
        findings.add(HealthFinding(
          title: 'تعديل وقود طويل المدى يميل للفقر',
          explanation: 'متوسط LTFT هو ${ltft.mean!.toStringAsFixed(1)}% — '
              'ECU يضيف وقودًا بشكل دائم، مؤشر على تسرب هواء أو نقص ضغط وقود.',
          recommendation: 'افحص الخراطيم، حساس MAF، وضغط مضخة الوقود.',
          severity: HealthSeverity.warning,
          scoreImpact: -15,
        ));
      } else if (ltft.mean! < ltftRichThreshold) {
        findings.add(HealthFinding(
          title: 'تعديل وقود طويل المدى يميل للغنى',
          explanation: 'متوسط LTFT هو ${ltft.mean!.toStringAsFixed(1)}% — '
              'ECU يقلل وقودًا باستمرار، مؤشر على حاقنات مسربة أو ضغط وقود مرتفع.',
          recommendation: 'افحص الحاقنات وضغط قضيب الوقود.',
          severity: HealthSeverity.warning,
          scoreImpact: -15,
        ));
      }
    }

    final o2f = stats['o2_b1s1'];
    if (o2f != null && o2f.hasData && o2f.stdDev != null) {
      final engineRunning = rpm != null && rpm.median != null && rpm.median! > o2DetectionMinRpm;
      if (engineRunning && o2f.stdDev! < o2FrontStuckStdDev) {
        findings.add(HealthFinding(
          title: 'حساس أكسجين أمامي لا يتذبذب',
          explanation: 'الانحراف المعياري لحساس البنك 1 الأمامي '
              '${o2f.stdDev!.toStringAsFixed(3)} فولت فقط، بينما المتوقع '
              'تذبذب سريع بين ~0.1V و~0.9V مع محرك يعمل بحمل.',
          recommendation: 'الحساس قد يكون متأخرًا أو عالقًا. استبداله يحسّن كفاءة الوقود.',
          severity: HealthSeverity.warning,
          scoreImpact: -10,
        ));
      }
    }

    final o2r = stats['o2_b1s2'];
    if (o2r != null && o2r.hasData && o2r.stdDev != null) {
      if (o2r.stdDev! > o2RearOscillatingStdDev) {
        findings.add(HealthFinding(
          title: 'حساس أكسجين خلفي متذبذب',
          explanation: 'الحساس الخلفي (بنك 1 - حساس 2) يتذبذب بانحراف '
              '${o2r.stdDev!.toStringAsFixed(3)} فولت، بينما المتوقع أن يكون '
              'مستقرًا نسبيًا (~0.6–0.8V) لو كان الكتلايزر سليمًا.',
          recommendation: 'احتمال ضعف في كفاءة المحول الحفّاز. قد يظهر كود P0420 لاحقًا.',
          severity: HealthSeverity.warning,
          scoreImpact: -15,
        ));
      }
    }

    // ═══════════════════════ قواعد عامة ═══════════════════════
    if (sec < shortSessionSec) {
      findings.add(HealthFinding(
        title: 'جلسة تسجيل قصيرة',
        explanation: 'مدة الجلسة ${sec.toStringAsFixed(0)} ثانية فقط — '
            'أقل من الحد الأدنى للتحليل الموثوق.',
        recommendation: 'سجّل جلسة قيادة أطول (5 دقائق فأكثر) لتحليل أدق.',
        severity: HealthSeverity.info,
        scoreImpact: 0,
      ));
    }

    findings.sort((a, b) {
      int rank(HealthSeverity s) {
        switch (s) {
          case HealthSeverity.critical:
            return 0;
          case HealthSeverity.warning:
            return 1;
          case HealthSeverity.info:
            return 2;
        }
      }

      return rank(a.severity).compareTo(rank(b.severity));
    });

    return LogAnalysisReport(
      rowCount: samples.length,
      duration: duration,
      samplingHz: hz,
      sessionStart: start,
      findings: findings,
      stats: stats,
      missingSensorKeys: missing,
    );
  }

  // ─── Helpers ───────────────────────────────────────────────

  static List<num> _numericValues(List<LogSample> samples, String key) {
    final out = <num>[];
    for (final s in samples) {
      final v = s.values[key];
      if (v != null) out.add(v);
    }
    return out;
  }

  static ColumnStats _computeStats(String key, List<num> values) {
    if (values.isEmpty) {
      return ColumnStats(
        key: key,
        validCount: 0,
        min: null,
        max: null,
        mean: null,
        stdDev: null,
        median: null,
      );
    }
    final sorted = [...values]..sort();
    final minV = sorted.first;
    final maxV = sorted.last;
    final meanV = values.fold<double>(0, (a, b) => a + b.toDouble()) / values.length;
    final variance =
        values.fold<double>(0, (a, b) => a + math.pow(b - meanV, 2).toDouble()) / values.length;
    final med = sorted.length.isOdd
        ? sorted[sorted.length ~/ 2].toDouble()
        : (sorted[sorted.length ~/ 2 - 1] + sorted[sorted.length ~/ 2]) / 2.0;

    return ColumnStats(
      key: key,
      validCount: values.length,
      min: minV,
      max: maxV,
      mean: meanV,
      stdDev: math.sqrt(variance),
      median: med,
    );
  }

  /// اسم عربي لعمود — إن لم يكن معروفًا في PidRegistry نرجع المفتاح الخام.
  static String labelFor(String key) {
    try {
      return PidRegistry.byKey(key).nameAr;
    } catch (_) {
      return key;
    }
  }

  static String unitFor(String key) {
    try {
      return PidRegistry.byKey(key).unit;
    } catch (_) {
      return '';
    }
  }
}
