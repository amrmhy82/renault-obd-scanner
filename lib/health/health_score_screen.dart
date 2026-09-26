import 'dart:async';
import 'package:flutter/material.dart';
import '../core/elm327_session.dart';
import '../telemetry/live_telemetry_service.dart';
import '../telemetry/vehicle_state.dart';
import 'health_finding.dart';
import 'health_score_engine.dart';

class HealthScoreScreen extends StatefulWidget {
  final Elm327Session session;
  final LiveTelemetryService telemetryService;

  const HealthScoreScreen({
    super.key,
    required this.session,
    required this.telemetryService,
  });

  @override
  State<HealthScoreScreen> createState() => _HealthScoreScreenState();
}

class _HealthScoreScreenState extends State<HealthScoreScreen> {
  StreamSubscription<VehicleState>? _sub;
  VehicleState _state = VehicleState.initial();
  List<String> _dtcCodes = [];
  bool _loadingDtc = false;
  bool _dtcScannedOnce = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.telemetryService.stream.listen((s) {
      if (mounted) setState(() => _state = s);
    });
    _refreshDtc();
  }

  Future<void> _refreshDtc() async {
    setState(() => _loadingDtc = true);
    try {
      final codes = await widget.session.readRawDtcs();
      if (mounted) {
        setState(() {
          _dtcCodes = codes;
          _dtcScannedOnce = true;
        });
      }
    } catch (_) {
      // نتجاهل الخطأ؛ يبقى _dtcScannedOnce كما كان فيؤثر بصدق على نسبة الثقة
    } finally {
      if (mounted) setState(() => _loadingDtc = false);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Color _scoreColor(int score) {
    if (score >= 85) return Colors.green;
    if (score >= 60) return Colors.orange;
    return Colors.red;
  }

  Color _severityColor(HealthSeverity s) {
    switch (s) {
      case HealthSeverity.critical:
        return Colors.red;
      case HealthSeverity.warning:
        return Colors.orange;
      case HealthSeverity.info:
        return Colors.blue;
    }
  }

  IconData _severityIcon(HealthSeverity s) {
    switch (s) {
      case HealthSeverity.critical:
        return Icons.dangerous;
      case HealthSeverity.warning:
        return Icons.warning_amber_rounded;
      case HealthSeverity.info:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = HealthScoreEngine.evaluate(_state, _dtcCodes, dtcScanned: _dtcScannedOnce);
    return Scaffold(
      appBar: AppBar(
        title: const Text('حالة السيارة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadingDtc ? null : _refreshDtc,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                Container(
                  width: 140,
                  height: 140,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _scoreColor(report.score), width: 8),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${report.score}',
                        style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: _scoreColor(report.score)),
                      ),
                      const Text('من 100', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'مستوى الثقة: ${report.confidencePercent}%',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'مبني على ${report.availableIndicatorsAr.length} من ${report.availableIndicatorsAr.length + report.missingIndicatorsAr.length} مؤشر متاح',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          if (report.confidencePercent < 40)
            Container(
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'بيانات غير كافية بعد لتقييم موثوق — انتظر اتصالًا أطول بالسيارة قبل الاعتماد على هذا الرقم.',
                      style: TextStyle(color: Colors.orange),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 24),
          if (report.findings.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green),
                    SizedBox(width: 12),
                    Expanded(child: Text('لا توجد ملاحظات حاليًا ضمن المؤشرات المتاحة.')),
                  ],
                ),
              ),
            ),
          ...report.findings.map((f) => Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(_severityIcon(f.severity), color: _severityColor(f.severity)),
                          const SizedBox(width: 8),
                          Expanded(child: Text(f.title, style: const TextStyle(fontWeight: FontWeight.bold))),
                          Text('${f.scoreImpact}',
                              style: TextStyle(color: _severityColor(f.severity), fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(f.explanation),
                      const SizedBox(height: 8),
                      Text('التوصية: ${f.recommendation}', style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              )),
          const SizedBox(height: 24),
          ExpansionTile(
            title: const Text('تفاصيل تغطية البيانات'),
            children: [
              ...report.availableIndicatorsAr.map((n) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.check_circle, color: Colors.green, size: 18),
                    title: Text(n),
                  )),
              ...report.missingIndicatorsAr.map((n) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.circle_outlined, color: Colors.grey, size: 18),
                    title: Text(n, style: const TextStyle(color: Colors.grey)),
                  )),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'ملاحظة: هذا تقييم مبني على قواعد ثابتة بسيطة (Rules Engine) وليس '
            'ذكاءً اصطناعيًا، ولا يغني عن فحص فني عند وجود أي عطل فعلي.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
