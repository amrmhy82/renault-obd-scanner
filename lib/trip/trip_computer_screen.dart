import 'package:flutter/material.dart';
import '../models/trip_point.dart';
import 'fuel_calibration_repository.dart';
import 'trip_computer.dart';
import 'trip_summary.dart';
import 'trip_summary_repository.dart';

/// حاسبة الرحلة: يعرض إحصائيات الرحلة الحالية (منذ الاتصال الآن) بالإضافة
/// لسجل الرحلات السابقة المحفوظة. لا يقرأ أي بيانات من ELM327 مباشرة —
/// فقط يحسب من نقاط مُجمَّعة مسبقًا (فصل واضح بين العرض والبروتوكول).
class TripComputerScreen extends StatefulWidget {
  final List<TripPoint> Function() getCurrentTripPoints;
  final TripSummaryRepository tripSummaryRepository;

  const TripComputerScreen({
    super.key,
    required this.getCurrentTripPoints,
    required this.tripSummaryRepository,
  });

  @override
  State<TripComputerScreen> createState() => _TripComputerScreenState();
}

class _TripComputerScreenState extends State<TripComputerScreen> {
  final FuelCalibrationRepository _fuelCalibrationRepository = FuelCalibrationRepository();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fuelCalibrationRepository.load().then((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0) return '$h س $m د';
    return '$m د';
  }

  String _formatDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  Widget _statRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _statsCard(String title, TripStats stats, {DateTime? date}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (date != null) Text(_formatDate(date), style: const TextStyle(color: Colors.grey)),
              ],
            ),
            const Divider(),
            if (stats.pointCount < 2)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('لا توجد بيانات كافية بعد.', style: TextStyle(color: Colors.grey)),
              )
            else ...[
              _statRow('المسافة', '${stats.distanceKm.toStringAsFixed(1)} كم'),
              _statRow('المدة', _formatDuration(stats.duration)),
              _statRow('متوسط السرعة', '${stats.avgSpeedKmh.toStringAsFixed(1)} كم/س'),
              _statRow('أقصى سرعة', '${stats.maxSpeedKmh} كم/س'),
              _statRow('متوسط الدورات', '${stats.avgRpm.toStringAsFixed(0)} RPM'),
              _statRow('أقصى دورات', '${stats.maxRpm} RPM'),
              if (stats.coolantMinC != null)
                _statRow('حرارة التبريد (أدنى/أقصى)', '${stats.coolantMinC}° / ${stats.coolantMaxC}°'),
              _statRow(
                stats.isCalibratedEstimate ? 'الوقود المقدّر (معايَر)' : 'الوقود المقدّر (تقريبي عام)',
                '${stats.estimatedFuelLiters.toStringAsFixed(1)} لتر',
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final currentStats = TripComputer.compute(
      widget.getCurrentTripPoints(),
      fuelConsumptionLPer100Km: _fuelCalibrationRepository.currentRateLPer100Km,
      isCalibratedRate: _fuelCalibrationRepository.isCalibrated,
    );
    final pastTrips = widget.tripSummaryRepository.trips;

    return Scaffold(
      appBar: AppBar(
        title: const Text('حاسبة الرحلة'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: () => setState(() {}))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _statsCard('الرحلة الحالية (منذ الاتصال الآن)', currentStats),
          const SizedBox(height: 8),
          if (!_fuelCalibrationRepository.isCalibrated)
            const Text(
              'الوقود المقدّر مبني حاليًا على معدل افتراضي عام (7.5 لتر/100كم). '
              'أضف تعبئة وقود فعلية في "معايرة استهلاك الوقود" ليصبح الرقم خاصًا بسيارتك.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            )
          else
            const Text(
              'الوقود المقدّر مبني على متوسط آخر تعبئاتك الفعلية — أدق من الرقم الافتراضي، لكنه يبقى تقديرًا وليس قراءة حساس مباشرة.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          const SizedBox(height: 24),
          Text('الرحلات السابقة (${pastTrips.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          if (pastTrips.isEmpty)
            const Text('لا توجد رحلات محفوظة بعد. تُحفظ الرحلة تلقائيًا عند قطع الاتصال بالمحول.',
                style: TextStyle(color: Colors.grey)),
          ...pastTrips.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _statsCard('رحلة ${_formatDate(t.startedAt)}', t.stats, date: t.startedAt),
              )),
        ],
      ),
    );
  }
}
