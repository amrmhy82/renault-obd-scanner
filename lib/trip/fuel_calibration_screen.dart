import 'package:flutter/material.dart';
import 'fuel_calibration.dart';
import 'fuel_calibration_repository.dart';

class FuelCalibrationScreen extends StatefulWidget {
  const FuelCalibrationScreen({super.key});

  @override
  State<FuelCalibrationScreen> createState() => _FuelCalibrationScreenState();
}

class _FuelCalibrationScreenState extends State<FuelCalibrationScreen> {
  final FuelCalibrationRepository _repo = FuelCalibrationRepository();
  bool _loading = true;
  final _litersController = TextEditingController();
  final _distanceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _repo.load();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _add() async {
    final liters = double.tryParse(_litersController.text.trim());
    final distance = double.tryParse(_distanceController.text.trim());
    if (liters == null || distance == null || distance <= 0) return;
    await _repo.addEntry(FuelCalibration(litersAdded: liters, distanceKm: distance, recordedAt: DateTime.now()));
    _litersController.clear();
    _distanceController.clear();
    if (mounted) setState(() {});
  }

  Future<void> _clear() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('مسح معايرة الاستهلاك'),
        content: const Text('سيعود التطبيق لاستخدام الرقم الافتراضي العام لتقدير الوقود. متابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('مسح')),
        ],
      ),
    );
    if (confirm == true) {
      await _repo.clear();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final rate = _repo.currentRateLPer100Km;
    return Scaffold(
      appBar: AppBar(title: const Text('معايرة استهلاك الوقود')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: _repo.isCalibrated ? Colors.green.shade50 : Colors.grey.shade100,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _repo.isCalibrated ? 'المعدل الحالي (معايَر من بيانات سيارتك)' : 'المعدل الحالي (افتراضي عام)',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text('${rate.toStringAsFixed(2)} لتر/100كم',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                  if (!_repo.isCalibrated)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'أضف تعبئة واحدة على الأقل ليصبح هذا الرقم خاصًا بسيارتك بدل الرقم العام.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('إضافة قياس تعبئة جديد', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
            controller: _litersController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'كمية الوقود المُضافة (لتر)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _distanceController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'المسافة المقطوعة منذ آخر تعبئة (كم)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          const Text(
            'أدخل هذا عند كل تعبئة وقود: كمية الوقود التي أضفتها الآن، والمسافة '
            'التي قطعتها منذ آخر تعبئة سابقة (من عداد الكيلومترات).',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _add,
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('إضافة'),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('القياسات المحفوظة (${_repo.entries.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
              if (_repo.isCalibrated)
                TextButton(onPressed: _clear, child: const Text('مسح الكل', style: TextStyle(color: Colors.red))),
            ],
          ),
          ..._repo.entries.map((e) => Card(
                child: ListTile(
                  title: Text('${e.litersAdded.toStringAsFixed(1)} لتر / ${e.distanceKm.toStringAsFixed(0)} كم'),
                  subtitle: Text('المعدل: ${e.consumptionLPer100Km.toStringAsFixed(2)} لتر/100كم'),
                  trailing: Text(
                    '${e.recordedAt.year}/${e.recordedAt.month.toString().padLeft(2, '0')}/${e.recordedAt.day.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
              )),
        ],
      ),
    );
  }
}
