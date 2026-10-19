import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/elm327_session.dart';
import '../resources/renault_resource_capture_service.dart';

class RenaultResourceCaptureScreen extends StatefulWidget {
  final Elm327Session session;
  const RenaultResourceCaptureScreen({super.key, required this.session});
  @override
  State<RenaultResourceCaptureScreen> createState() => _RenaultResourceCaptureScreenState();
}

class _RenaultResourceCaptureScreenState extends State<RenaultResourceCaptureScreen> {
  Map<String, Object?>? _report;
  bool _running = false;
  String _step = '';

  Future<void> _run() async {
    setState(() { _running = true; _report = null; _step = 'بدء جمع الموارد'; });
    try {
      final report = await RenaultResourceCaptureService(widget.session).run(onStep: (step) {
        if (mounted) setState(() => _step = step);
      });
      if (mounted) setState(() => _report = report);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذر جمع الموارد: $error')));
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _share() async {
    final report = _report;
    if (report == null) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/renault_resource_capture.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    await Share.shareXFiles([XFile(file.path)], text: 'حزمة موارد Renault للقراءة فقط');
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('موارد Renault')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('جمع موارد للبحث والتطوير', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('يجمع التطبيق أدلة قراءة فقط من ECU والمحول. لا يرسل أوامر برمجة أو تهيئة أو تفعيل، ولا يستكشف عناوين CAN عشوائية.'),
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _running ? null : _run, icon: const Icon(Icons.travel_explore), label: Text(_running ? _step : 'جمع حزمة الموارد')),
          if (_running) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
          if (report != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: _share, icon: const Icon(Icons.ios_share), label: const Text('مشاركة الحزمة')),
            const SizedBox(height: 8),
            Text(const JsonEncoder.withIndent('  ').convert(report), style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          ],
        ],
      ),
    );
  }
}
