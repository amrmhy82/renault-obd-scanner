import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/elm327_session.dart';
import '../symptoms/symptom_diagnostic_service.dart';
import '../symptoms/symptom_models.dart';
import '../symptoms/symptom_registry.dart';

class SymptomScreen extends StatefulWidget {
  final Elm327Session session;
  const SymptomScreen({super.key, required this.session});
  @override
  State<SymptomScreen> createState() => _SymptomScreenState();
}

class _SymptomScreenState extends State<SymptomScreen> {
  SymptomReport? _report;
  bool _running = false;
  String _step = '';

  Future<void> _run(SymptomDefinition symptom) async {
    setState(() { _running = true; _report = null; _step = 'بدء الفحص'; });
    try {
      final report = await SymptomDiagnosticService(widget.session).run(symptom, onStep: (step) {
        if (mounted) setState(() => _step = step);
      });
      if (mounted) setState(() => _report = report);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر إكمال الفحص: $error')));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _export() async {
    final report = _report;
    if (report == null) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/symptom_report_${report.symptom.id}.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(report.toJson()));
    await Share.shareXFiles([XFile(file.path)], text: 'تقرير فحص العرض ${report.symptom.nameAr}');
  }

  Color _confidence(ValueConfidence value) => switch (value) {
        ValueConfidence.high => Colors.green,
        ValueConfidence.medium => Colors.orange,
        ValueConfidence.low || ValueConfidence.unconfirmed => Colors.grey,
      };

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('مشاكل السيارة')),
      body: report == null
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('اختر العرض الذي تريد فحصه', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                const Text('سيقرأ التطبيق البيانات المرتبطة بالعرض ويعرض الأدلة والاحتمالات، دون تشخيص قطعي للقطعة.'),
                const SizedBox(height: 12),
                if (_running) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  Text(_step, textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                ],
                ...SymptomRegistry.all.map((symptom) => Card(
                  child: ListTile(
                    leading: Icon(Icons.manage_search, color: symptom.severity == SymptomSeverity.high ? Colors.red : Colors.blueGrey),
                    title: Text(symptom.nameAr),
                    subtitle: Text(symptom.descriptionAr),
                    trailing: const Icon(Icons.chevron_left),
                    enabled: !_running,
                    onTap: () => _confirm(symptom),
                  ),
                )),
              ],
            )
          : _reportView(report),
    );
  }

  Future<void> _confirm(SymptomDefinition symptom) async {
    final run = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(symptom.nameAr),
      content: const Text('سيجري فحص مخصص لمدة قصيرة ويقرأ أوامر تشخيصية فقط. أبق السيارة في وضع آمن أثناء الفحص.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('بدء الفحص'))],
    ));
    if (run == true) await _run(symptom);
  }

  Widget _reportView(SymptomReport report) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(report.symptom.nameAr, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          Text('تقرير ${report.symptom.id} • ${report.timestamp}'),
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: _export, icon: const Icon(Icons.ios_share), label: const Text('تصدير التقرير')),
          OutlinedButton.icon(onPressed: () => setState(() => _report = null), icon: const Icon(Icons.refresh), label: const Text('فحص عرض آخر')),
          const SizedBox(height: 8),
          const Text('الأدلة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ...report.evidence.map((e) => Card(child: ListTile(title: Text(e.title), subtitle: Text('${e.value}\n${e.supportingData}\nالجودة: ${e.quality.name} • العمر: ${e.ageMs ?? "غير متاح"} ms • المعدل: ${e.rateHz?.toStringAsFixed(1) ?? "غير متاح"} Hz • الحالة: ${e.state.name}'), isThreeLine: true, trailing: Text(e.confidence.name, style: TextStyle(color: _confidence(e.confidence))))),
          const Text('الاستنتاجات', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ...report.conclusions.map((e) => ListTile(leading: const Icon(Icons.lightbulb_outline), title: Text(e))),
          const Text('حدود النتيجة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          ...report.uncertainties.map((e) => ListTile(leading: const Icon(Icons.info_outline), title: Text(e))),
        ],
      );
}
