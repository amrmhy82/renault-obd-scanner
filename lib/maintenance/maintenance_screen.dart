import 'package:flutter/material.dart';
import 'maintenance_item.dart';
import 'maintenance_repository.dart';

class MaintenanceScreen extends StatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  State<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends State<MaintenanceScreen> {
  final MaintenanceRepository _repo = MaintenanceRepository();
  bool _loading = true;
  final TextEditingController _mileageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _repo.load();
    _mileageController.text = _repo.currentMileage?.toString() ?? '';
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _saveMileage() async {
    final km = int.tryParse(_mileageController.text.trim());
    if (km == null) return;
    await _repo.setCurrentMileage(km);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تحديث عداد الكيلومترات')));
  }

  Future<void> _recordService(MaintenanceItem item) async {
    final kmController = TextEditingController(
      text: _repo.currentMileage?.toString() ?? item.lastServiceKm?.toString() ?? '',
    );
    final costController = TextEditingController(text: item.cost?.toString() ?? '');
    final workshopController = TextEditingController(text: item.workshop ?? '');
    final notesController = TextEditingController(text: item.notes ?? '');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('تسجيل صيانة: ${item.nameAr}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: kmController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'الكيلومترات عند الصيانة'),
              ),
              TextField(
                controller: costController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'التكلفة (اختياري)'),
              ),
              TextField(
                controller: workshopController,
                decoration: const InputDecoration(labelText: 'الورشة (اختياري)'),
              ),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (confirmed != true) return;
    final km = int.tryParse(kmController.text.trim());
    if (km == null) return;
    await _repo.recordService(
      item.id,
      atKm: km,
      cost: double.tryParse(costController.text.trim()),
      workshop: workshopController.text.trim().isEmpty ? null : workshopController.text.trim(),
      notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
    );
    if (mounted) setState(() {});
  }

  Color _statusColor(int? remaining) {
    if (remaining == null) return Colors.grey;
    if (remaining < 0) return Colors.red;
    if (remaining < 1000) return Colors.orange;
    return Colors.green;
  }

  String _statusText(int? remaining) {
    if (remaining == null) return 'أدخل عداد الكيلومترات وسجّل الصيانة الأخيرة لحساب الموعد القادم';
    if (remaining < 0) return 'متأخر بمقدار ${-remaining} كم عن الموعد المقترح';
    return 'متبقي تقريبًا $remaining كم';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('سجل الصيانة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _mileageController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'عداد الكيلومترات الحالي'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: _saveMileage, child: const Text('حفظ')),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'الفترات أدناه تقديرات عامة شائعة — راجع دليل مالك رينو فلوانس لتأكيد الفترات الدقيقة لسيارتك.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),
          ..._repo.items.map((item) {
            final remaining = item.remainingKm(_repo.currentMileage);
            return Card(
              child: ListTile(
                title: Text(item.nameAr, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  '${item.lastServiceKm != null ? "آخر صيانة عند ${item.lastServiceKm} كم" : "لم تُسجَّل صيانة بعد"}\n'
                  '${_statusText(remaining)}',
                ),
                isThreeLine: true,
                leading: CircleAvatar(
                  backgroundColor: _statusColor(remaining),
                  child: const Icon(Icons.build, color: Colors.white, size: 18),
                ),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => _recordService(item),
              ),
            );
          }),
        ],
      ),
    );
  }
}
