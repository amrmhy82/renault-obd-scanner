import 'package:flutter/material.dart';
import 'mileage_store.dart';
import 'vehicle_profile.dart';
import 'vehicle_profile_repository.dart';

class VehicleProfileScreen extends StatefulWidget {
  const VehicleProfileScreen({super.key});

  @override
  State<VehicleProfileScreen> createState() => _VehicleProfileScreenState();
}

class _VehicleProfileScreenState extends State<VehicleProfileScreen> {
  final VehicleProfileRepository _repo = VehicleProfileRepository();
  bool _loading = true;

  final _make = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController();
  final _vin = TextEditingController();
  final _engine = TextEditingController();
  final _transmission = TextEditingController();
  final _fuelType = TextEditingController();
  final _plate = TextEditingController();
  final _adapter = TextEditingController();
  final _mileage = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _repo.load();
    final p = _repo.profile;
    _make.text = p.make;
    _model.text = p.model;
    _year.text = p.year?.toString() ?? '';
    _vin.text = p.vin ?? '';
    _engine.text = p.engine ?? '';
    _transmission.text = p.transmission ?? '';
    _fuelType.text = p.fuelType ?? '';
    _plate.text = p.plateNumber ?? '';
    _adapter.text = p.obdAdapterName ?? '';
    final mileage = await MileageStore.get();
    _mileage.text = mileage?.toString() ?? '';
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final updated = VehicleProfile(
      make: _make.text.trim().isEmpty ? 'Renault' : _make.text.trim(),
      model: _model.text.trim().isEmpty ? 'Fluence' : _model.text.trim(),
      year: int.tryParse(_year.text.trim()),
      vin: _vin.text.trim().isEmpty ? null : _vin.text.trim(),
      engine: _engine.text.trim().isEmpty ? null : _engine.text.trim(),
      transmission: _transmission.text.trim().isEmpty ? null : _transmission.text.trim(),
      fuelType: _fuelType.text.trim().isEmpty ? null : _fuelType.text.trim(),
      plateNumber: _plate.text.trim().isEmpty ? null : _plate.text.trim(),
      obdAdapterName: _adapter.text.trim().isEmpty ? null : _adapter.text.trim(),
    );
    await _repo.save(updated);
    final km = int.tryParse(_mileage.text.trim());
    if (km != null) await MileageStore.set(km);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حفظ بيانات السيارة')));
  }

  Widget _field(String label, TextEditingController c, {TextInputType? type}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: type,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('بيانات السيارة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _field('الشركة المصنّعة', _make),
          _field('الموديل', _model),
          _field('سنة الصنع', _year, type: TextInputType.number),
          _field('رقم الهيكل (VIN)', _vin),
          _field('المحرك (مثال: 1.6L K4M)', _engine),
          _field('ناقل الحركة', _transmission),
          _field('نوع الوقود', _fuelType),
          _field('رقم اللوحة', _plate),
          _field('اسم/موديل محول OBD2', _adapter),
          const Divider(),
          _field('عداد الكيلومترات الحالي', _mileage, type: TextInputType.number),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _save,
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}
