import 'dart:io';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../data/data_logger_service.dart';
import 'log_analysis_screen.dart';

/// شاشة إدارة ملفات تسجيل البيانات الخام (CSV). منفصلة عن TripLogScreen
/// (رسوم بيانية لثلاث قيم فقط) لأن هذه تتعامل مع ملفات كاملة على القرص
/// قابلة للتصدير والتحليل التلقائي.
class DataLogsScreen extends StatefulWidget {
  const DataLogsScreen({super.key});

  @override
  State<DataLogsScreen> createState() => _DataLogsScreenState();
}

class _DataLogsScreenState extends State<DataLogsScreen> {
  final DataLoggerService _logger = DataLoggerService();
  List<File> _files = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final files = await _logger.listLogs();
    if (mounted) {
      setState(() {
        _files = files;
        _loading = false;
      });
    }
  }

  void _openAnalysis(File f) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => LogAnalysisScreen(file: f)));
  }

  Future<void> _share(File f) async {
    try {
      await Share.shareXFiles([XFile(f.path, mimeType: 'text/csv')], subject: f.path.split('/').last);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تعذّرت المشاركة: $e')));
      }
    }
  }

  Future<void> _delete(File f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف ملف السجل'),
        content: Text('سيُحذف ${f.path.split('/').last} نهائيًا. متابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await _logger.deleteLog(f);
    await _load();
  }

  Future<void> _deleteAll() async {
    if (_files.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف كل الملفات'),
        content: Text('سيتم حذف ${_files.length} ملف سجل دفعة واحدة. متابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حذف الكل', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    await _logger.deleteAllLogs();
    await _load();
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _fmtDateTime(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل البيانات الكامل (CSV)'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _load),
          if (_files.isNotEmpty)
            IconButton(icon: const Icon(Icons.delete_sweep_outlined), tooltip: 'حذف الكل', onPressed: _deleteAll),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _files.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'لا توجد ملفات سجل بعد.\nيبدأ التسجيل تلقائيًا عند فتح لوحة البيانات بعد الاتصال بالسيارة.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _files.length,
                  itemBuilder: (_, i) {
                    final f = _files[i];
                    final stat = f.statSync();
                    final name = f.path.split('/').last;
                    return Card(
                      child: ListTile(
                        leading: const Icon(Icons.description_outlined, color: Colors.blueGrey),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(
                          '${_fmtDateTime(stat.modified)}  •  ${_fmtSize(stat.size)}\nاضغط لعرض التحليل التلقائي',
                          style: const TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.analytics_outlined), tooltip: 'تحليل', onPressed: () => _openAnalysis(f)),
                            IconButton(icon: const Icon(Icons.share_outlined), tooltip: 'مشاركة CSV', onPressed: () => _share(f)),
                            IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'حذف', onPressed: () => _delete(f)),
                          ],
                        ),
                        onTap: () => _openAnalysis(f),
                      ),
                    );
                  },
                ),
    );
  }
}
