import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/elm327_session.dart';
import '../quick_scan/quick_scan_service.dart';
import '../quick_scan/quick_scan_history.dart';
import '../vehicle/vehicle_profile_repository.dart';

class QuickScanScreen extends StatefulWidget {
  final Elm327Session session;
  const QuickScanScreen({super.key, required this.session});
  @override
  State<QuickScanScreen> createState() => _QuickScanScreenState();
}

class _QuickScanScreenState extends State<QuickScanScreen> {
  QuickScanReport? _report;
  bool _running = false;
  String _step = '';
  bool _hasSavedReport = false;

  @override
  void initState() {
    super.initState();
    _loadSavedState();
  }

  Future<void> _loadSavedState() async {
    final saved = await QuickScanHistory().load();
    if (mounted) setState(() => _hasSavedReport = saved != null);
  }

  Future<void> _run() async {
    setState(() { _running = true; _report = null; _step = 'بدء الفحص'; });
    try {
      final report = await QuickScanService(widget.session).run(onStep: (step) { if (mounted) setState(() => _step = step); });
      await QuickScanHistory().save(report);
      if (report.vin != null) {
        final profiles = VehicleProfileRepository();
        await profiles.load();
        final profile = profiles.profile;
        profile.vin = report.vin;
        await profiles.save(profile);
      }
      if (mounted) setState(() { _report = report; _hasSavedReport = true; });
    } finally { if (mounted) setState(() => _running = false); }
  }

  Future<void> _export() async {
    final report = _report;
    if (report == null) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/quick_scan_report.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(report.toJson()));
    await Share.shareXFiles([XFile(file.path)], text: 'تقرير الفحص السريع');
  }

  Future<void> _exportSaved() async {
    final saved = await QuickScanHistory().load();
    if (saved == null) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/last_quick_scan_report.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(saved));
    await Share.shareXFiles([XFile(file.path)], text: 'آخر تقرير فحص سريع محفوظ');
  }

  Color _color(QuickScanSeverity s) => switch (s) { QuickScanSeverity.ok => Colors.green, QuickScanSeverity.attention => Colors.orange, QuickScanSeverity.unavailable => Colors.grey };

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('الفحص السريع')),
      body: report == null ? ListView(padding: const EdgeInsets.all(16), children: [
        const Text('فحص عملي لحالة السيارة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('يجمع المعلومات الأساسية والأعطال والجاهزية وFreeze Frame في تقرير واحد. لا ينفذ أي أمر كتابة.'),
        const SizedBox(height: 20),
        FilledButton.icon(onPressed: _running ? null : _run, icon: const Icon(Icons.play_arrow), label: Text(_running ? _step : 'بدء الفحص')),
        if (_hasSavedReport) const Padding(padding: EdgeInsets.only(top: 12), child: Text('يوجد تقرير محفوظ من آخر فحص. شغّل فحصًا جديدًا لتحديثه.', style: TextStyle(color: Colors.blueGrey))),
        if (_hasSavedReport) OutlinedButton.icon(onPressed: _exportSaved, icon: const Icon(Icons.history), label: const Text('مشاركة آخر تقرير محفوظ')),
        if (_running) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
      ]) : ListView(padding: const EdgeInsets.all(16), children: [
        Text(report.summary, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        if (report.vin != null) Text('VIN: ${report.vin}'),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _export, icon: const Icon(Icons.ios_share), label: const Text('تصدير التقرير')),
        OutlinedButton.icon(onPressed: _run, icon: const Icon(Icons.refresh), label: const Text('إعادة الفحص')),
        const SizedBox(height: 8),
        ...report.items.map((item) => Card(child: ListTile(leading: Icon(Icons.circle, size: 14, color: _color(item.severity)), title: Text(item.title), subtitle: Text('${item.value}\n${item.detail}'), isThreeLine: true))),
        if (report.recommendations.isNotEmpty) ...[const Text('التوصيات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), ...report.recommendations.map((r) => ListTile(leading: const Icon(Icons.arrow_back), title: Text(r)))],
      ]),
    );
  }
}
