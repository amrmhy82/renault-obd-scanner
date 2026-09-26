import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../data/log_analyzer.dart';
import '../health/health_finding.dart';

/// شاشة تحليل جلسة تسجيل واحدة — تعرض ملاحظات القواعد تلقائيًا + إحصاءات
/// كل حساس. لا تُجري أي اتصال بالسيارة، تعمل فقط على ملف CSV محفوظ.
class LogAnalysisScreen extends StatefulWidget {
  final File file;
  const LogAnalysisScreen({super.key, required this.file});

  @override
  State<LogAnalysisScreen> createState() => _LogAnalysisScreenState();
}

class _LogAnalysisScreenState extends State<LogAnalysisScreen> {
  LogAnalysisReport? _report;
  ParsedLog? _parsed;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final parsed = await LogAnalyzer.parseCsv(widget.file);
    if (!mounted) return;
    if (parsed == null) {
      setState(() {
        _loading = false;
        _error = 'تعذّرت قراءة الملف — قد يكون تالفًا أو أكبر من الحد المدعوم.';
      });
      return;
    }
    final report = LogAnalyzer.analyze(parsed);
    setState(() {
      _parsed = parsed;
      _report = report;
      _loading = false;
    });
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

  String _fmtDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    final s = d.inSeconds % 60;
    if (h > 0) return '$h س $m د $s ث';
    if (m > 0) return '$m د $s ث';
    return '$s ث';
  }

  String _fmtDateTime(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _fmtNum(num? v) {
    if (v == null) return '--';
    if (v == v.roundToDouble()) return v.round().toString();
    return v.toStringAsFixed(2);
  }

  String _buildTextReport() {
    final r = _report!;
    final buf = StringBuffer();
    buf.writeln('تقرير تحليل جلسة OBD2');
    buf.writeln('الملف: ${widget.file.path.split('/').last}');
    if (r.sessionStart != null) {
      buf.writeln('بداية الجلسة: ${_fmtDateTime(r.sessionStart!)}');
    }
    buf.writeln('المدة: ${_fmtDuration(r.duration)}');
    buf.writeln('عدد الصفوف: ${r.rowCount} (بمعدل ${r.samplingHz.toStringAsFixed(1)} Hz)');
    buf.writeln();
    buf.writeln('--- الملاحظات (${r.findings.length}) ---');
    if (r.findings.isEmpty) {
      buf.writeln('لا ملاحظات.');
    } else {
      for (final f in r.findings) {
        buf.writeln('• [${f.severity.name.toUpperCase()}] ${f.title}');
        buf.writeln('  ${f.explanation}');
        buf.writeln('  التوصية: ${f.recommendation}');
        buf.writeln();
      }
    }
    if (r.missingSensorKeys.isNotEmpty) {
      buf.writeln('--- حساسات لم تُرجع أي بيانات ---');
      for (final k in r.missingSensorKeys) {
        buf.writeln('• ${LogAnalyzer.labelFor(k)} ($k)');
      }
    }
    return buf.toString();
  }

  Future<void> _shareReport() async {
    if (_report == null) return;
    final text = _buildTextReport();
    await Share.share(text, subject: 'تقرير تحليل ${widget.file.path.split('/').last}');
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.file.path.split('/').last;
    return Scaffold(
      appBar: AppBar(
        title: Text(fileName, overflow: TextOverflow.ellipsis),
        actions: [
          if (_report != null)
            IconButton(
              icon: const Icon(Icons.share_outlined),
              tooltip: 'مشاركة التقرير نصًّا',
              onPressed: _shareReport,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    final r = _report!;
    final p = _parsed!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _summaryCard(r),
        const SizedBox(height: 16),
        Text('الملاحظات (${r.findings.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        if (r.findings.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: 12),
                  Expanded(child: Text('لا توجد ملاحظات ضمن القواعد المتاحة.')),
                ],
              ),
            ),
          ),
        ...r.findings.map(_findingCard),
        const SizedBox(height: 24),
        Text('إحصاءات الحساسات (${r.stats.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        ...p.pidKeys.where((k) => r.stats[k]?.hasData ?? false).map((k) => _statRow(k, r.stats[k]!)),
        if (r.missingSensorKeys.isNotEmpty) ...[
          const SizedBox(height: 16),
          ExpansionTile(
            title: Text(
              'حساسات لم تُرجع أي بيانات (${r.missingSensorKeys.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            children: r.missingSensorKeys
                .map((k) => ListTile(
                      dense: true,
                      leading: const Icon(Icons.circle_outlined, color: Colors.grey, size: 18),
                      title: Text(LogAnalyzer.labelFor(k)),
                      subtitle: Text(k, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ))
                .toList(),
          ),
        ],
        const SizedBox(height: 24),
        const Text(
          'هذا التحليل مبني على قواعد ثابتة (Rules Engine) وليس ذكاءً اصطناعيًا، '
          'والعتبات المستخدمة تقريبية عامة وليست مُعايرة خصيصًا لهذه السيارة بعد.',
          style: TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ],
    );
  }

  Widget _summaryCard(LogAnalysisReport r) {
    return Card(
      color: Colors.blueGrey.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics_outlined, color: Colors.blueGrey.shade700),
                const SizedBox(width: 8),
                const Text('ملخص الجلسة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const Divider(),
            _kv('المدة', _fmtDuration(r.duration)),
            _kv('عدد الصفوف', '${r.rowCount}'),
            _kv('معدل التسجيل', '${r.samplingHz.toStringAsFixed(1)} Hz'),
            if (r.sessionStart != null) _kv('بداية الجلسة', _fmtDateTime(r.sessionStart!)),
            _kv('عدد الملاحظات', '${r.findings.length}'),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(k, style: const TextStyle(color: Colors.grey)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _findingCard(HealthFinding f) {
    final c = _severityColor(f.severity);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_severityIcon(f.severity), color: c),
                const SizedBox(width: 8),
                Expanded(child: Text(f.title, style: const TextStyle(fontWeight: FontWeight.bold))),
                if (f.scoreImpact != 0)
                  Text('${f.scoreImpact}', style: TextStyle(color: c, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(f.explanation),
            const SizedBox(height: 8),
            Text('التوصية: ${f.recommendation}', style: const TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _statRow(String key, ColumnStats s) {
    final label = LogAnalyzer.labelFor(key);
    final unit = LogAnalyzer.unitFor(key);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14))),
                Text('${s.validCount} قراءة', style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                _miniStat('الأدنى', '${_fmtNum(s.min)} $unit'),
                _miniStat('المتوسط', '${_fmtNum(s.mean)} $unit'),
                _miniStat('الأقصى', '${_fmtNum(s.max)} $unit'),
                _miniStat('σ', _fmtNum(s.stdDev)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
