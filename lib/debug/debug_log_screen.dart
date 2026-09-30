import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../core/elm327_session.dart';

/// سجل تصحيح تقني (Observability) يعرض كل أمر أُرسل والرد الخام وزمن
/// الاستجابة، لتشخيص مشاكل اتصال حقيقية مع السيارة. لا يظهر للمستخدم
/// العادي إلا عبر قائمة "المزيد" — هذه ليست شاشة تشخيص سيارة، بل شاشة
/// تشخيص اتصال.
class DebugLogScreen extends StatefulWidget {
  final Elm327Session session;
  const DebugLogScreen({super.key, required this.session});

  @override
  State<DebugLogScreen> createState() => _DebugLogScreenState();
}

class _DebugLogScreenState extends State<DebugLogScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _exportCapture() async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/obd_raw_capture.json');
    await file.writeAsString(widget.session.rawCapture.toJson(), flush: true);
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Raw OBD diagnostic capture',
    );
  }

  String _fmtTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}.${t.millisecond.toString().padLeft(3, '0')}';

  String _cleanRaw(String raw) =>
      raw.replaceAll('\r', ' ').replaceAll('\n', ' ').replaceAll('>', '').trim();

  @override
  Widget build(BuildContext context) {
    final entries = widget.session.rawCapture.entries.reversed.toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل تصحيح الأخطاء (Debug)'),
        actions: [
          IconButton(
            tooltip: 'تصدير Raw Capture',
            icon: const Icon(Icons.ios_share),
            onPressed: entries.isEmpty ? null : _exportCapture,
          ),
          IconButton(
            tooltip: 'مسح السجل',
            icon: const Icon(Icons.delete_outline),
            onPressed: entries.isEmpty
                ? null
                : () => setState(() => widget.session.rawCapture.clear()),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('${entries.length}', style: const TextStyle(color: Colors.white70)),
            ),
          ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(child: Text('لا توجد أوامر مسجّلة بعد.', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: entries.length,
              itemBuilder: (context, i) {
                final e = entries[i];
                return Card(
                  color: e.isError ? Colors.red.shade50 : null,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_fmtTime(e.timestamp), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            Text('${e.latencyMs} ms', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('TX  ${e.command}',
                            style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                        Text(
                          'RX  ${_cleanRaw(e.rawResponse)}',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: e.isError ? Colors.red.shade700 : Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
