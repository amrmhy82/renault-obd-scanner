import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../certification/certification_service.dart';
import '../core/elm327_session.dart';

class CertificationScreen extends StatefulWidget {
  final Elm327Session session;
  const CertificationScreen({super.key, required this.session});
  @override
  State<CertificationScreen> createState() => _CertificationScreenState();
}

class _CertificationScreenState extends State<CertificationScreen> {
  CertificationReport? _report;
  bool _running = false;

  Future<void> _run() async {
    setState(() => _running = true);
    try {
      final report = await CertificationService(widget.session).run();
      if (mounted) setState(() => _report = report);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _export() async {
    final report = _report;
    if (report == null) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/phase_0_certification.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(report.toJson()));
    await Share.shareXFiles([XFile(file.path)], text: 'Phase 0 Certification Report');
  }

  Color _color(CertificationStatus status) => switch (status) {
        CertificationStatus.pass => Colors.green,
        CertificationStatus.fail => Colors.red,
        CertificationStatus.skipped => Colors.orange,
      };

  String _label(CertificationStatus status) => switch (status) {
        CertificationStatus.pass => 'نجح',
        CertificationStatus.fail => 'فشل',
        CertificationStatus.skipped => 'تخطّي',
      };

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('اعتماد Phase 0')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('اختبارات جاهزية الاتصال والتشخيص', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('الاختبارات التي تحتاج سيارة ومحولًا متصلًا تظهر كتخطّي بدل تسجيل نجاح غير موثّق.'),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _running ? null : _run, icon: const Icon(Icons.play_arrow), label: Text(_running ? 'جارٍ الاختبار...' : 'تشغيل الاعتماد')),
          if (report != null) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _export, icon: const Icon(Icons.file_download_outlined), label: const Text('تصدير التقرير')),
            const SizedBox(height: 12),
            ...report.results.map((r) => Card(
              child: ListTile(
                leading: Icon(r.status == CertificationStatus.pass ? Icons.check_circle : Icons.info, color: _color(r.status)),
                title: Text(r.title),
                subtitle: Text(r.details),
                trailing: Text(_label(r.status), style: TextStyle(color: _color(r.status), fontWeight: FontWeight.bold)),
              ),
            )),
          ],
        ],
      ),
    );
  }
}
