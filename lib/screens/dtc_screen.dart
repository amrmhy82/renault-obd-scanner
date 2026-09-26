import 'package:flutter/material.dart';
import '../core/elm327_session.dart';
import '../data/dtc_database.dart';
import '../diagnostics/dtc_history_entry.dart';
import '../diagnostics/dtc_history_repository.dart';

class DtcScreen extends StatefulWidget {
  final Elm327Session session;
  final DtcHistoryRepository historyRepository;

  const DtcScreen({
    super.key,
    required this.session,
    required this.historyRepository,
  });

  @override
  State<DtcScreen> createState() => _DtcScreenState();
}

class _DtcScreenState extends State<DtcScreen> {
  final DtcDatabase _dtcDatabase = DtcDatabase();
  List<String> _activeCodes = [];
  bool _loading = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _dtcDatabase.load();
    await _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _message = null;
    });
    try {
      final codes = await widget.session.readRawDtcs();
      await widget.historyRepository.recordScan(codes);
      setState(() {
        _activeCodes = codes;
        _message = codes.isEmpty ? 'لا توجد أعطال نشطة حاليًا.' : null;
      });
    } catch (e) {
      setState(() => _message = 'تعذّرت قراءة الأعطال: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _clear() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('تأكيد المسح'),
        content: const Text(
          'سيتم مسح جميع أكواد الأعطال وإطفاء ضوء المحرك (Check Engine). '
          'سيبقى السجل التاريخي محفوظًا حتى لو عاد الكود لاحقًا. '
          'إن لم يُصلح سبب العطل الفعلي فقد يعود الكود من جديد. متابعة؟',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('مسح')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    final ok = await widget.session.clearDtcs();
    if (ok) await widget.historyRepository.recordClear();
    setState(() {
      _loading = false;
      _message = ok ? 'تم مسح الأعطال بنجاح.' : 'فشل مسح الأعطال.';
    });
    await _scan(); // إعادة فحص فورية للتحقق (Verify) بعد المسح
  }

  String _formatDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  Color _sourceColor(DtcSource s) {
    switch (s) {
      case DtcSource.saeStandard:
        return Colors.green;
      case DtcSource.saeManufacturer:
        return Colors.blue;
      case DtcSource.nonStandardFormat:
        return Colors.deepOrange;
      case DtcSource.unknown:
        return Colors.grey;
    }
  }

  Widget _sourceChip(DtcSource src) {
    final c = _sourceColor(src);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
      child: Text(
        _dtcDatabase.sourceLabelAr(src),
        style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _historyTile(DtcHistoryEntry h) {
    return Card(
      child: ListTile(
        leading: Icon(
          h.isActive ? Icons.error : Icons.check_circle,
          color: h.isActive ? Colors.orange : Colors.green,
        ),
        title: Row(
          children: [
            Expanded(child: Text('${h.code} — ${h.isActive ? "نشط" : "تم مسحه"}')),
            _sourceChip(_dtcDatabase.sourceOf(h.code)),
          ],
        ),
        subtitle: Text(
          'أول ظهور: ${_formatDate(h.firstDetected)}  •  آخر ظهور: ${_formatDate(h.lastSeen)}\n'
          'عدد مرات التكرار: ${h.occurrences}'
          '${h.clearedAt != null ? "  •  آخر مسح: ${_formatDate(h.clearedAt!)}" : ""}',
        ),
        isThreeLine: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = widget.historyRepository.all;
    return Scaffold(
      appBar: AppBar(
        title: const Text('أكواد الأعطال (DTC)'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loading ? null : _scan),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(_message!, style: const TextStyle(color: Colors.grey)),
                  ),
                Text('الأعطال النشطة الآن (${_activeCodes.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ..._activeCodes.map((c) {
                  final src = _dtcDatabase.sourceOf(c);
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.orange),
                              const SizedBox(width: 8),
                              Text(c, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              const Spacer(),
                              _sourceChip(src),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(_dtcDatabase.describe(c)),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _activeCodes.isEmpty || _loading ? null : _clear,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('مسح الأعطال وإطفاء الضوء'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade600,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 8),
                Text('السجل التاريخي الكامل (${history.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (history.isEmpty)
                  const Text('لا يوجد سجل بعد.', style: TextStyle(color: Colors.grey)),
                ...history.map(_historyTile),
              ],
            ),
    );
  }
}
