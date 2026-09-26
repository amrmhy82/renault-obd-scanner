import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../models/trip_point.dart';
import '../services/trip_log_service.dart';
import 'data_logs_screen.dart';

class TripLogScreen extends StatefulWidget {
  final TripLogService tripLogService;
  const TripLogScreen({super.key, required this.tripLogService});

  @override
  State<TripLogScreen> createState() => _TripLogScreenState();
}

class _TripLogScreenState extends State<TripLogScreen> {
  Future<void> _clear() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('مسح سجل الرحلة'),
        content: const Text('سيتم حذف كل القراءات المسجلة في هذه الرحلة نهائيًا. متابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('مسح')),
        ],
      ),
    );
    if (confirm == true) {
      await widget.tripLogService.clear();
      if (mounted) setState(() {});
    }
  }

  List<FlSpot> _spots(num? Function(TripPoint) selector, List<TripPoint> points) {
    final spots = <FlSpot>[];
    for (int i = 0; i < points.length; i++) {
      final v = selector(points[i]);
      if (v != null) spots.add(FlSpot(i.toDouble(), v.toDouble()));
    }
    return spots;
  }

  Widget _chartCard(String title, List<FlSpot> spots, Color color) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            SizedBox(
              height: 160,
              child: spots.length < 2
                  ? const Center(child: Text('لا توجد بيانات كافية بعد', style: TextStyle(color: Colors.grey)))
                  : LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: true, drawVerticalLine: false),
                        titlesData: const FlTitlesData(
                          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(showTitles: true, reservedSize: 36),
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            color: color,
                            barWidth: 2,
                            dotData: const FlDotData(show: false),
                            belowBarData: BarAreaData(show: true, color: color.withOpacity(0.12)),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final points = widget.tripLogService.points;
    final speedSpots = _spots((p) => p.speedKmh, points);
    final rpmSpots = _spots((p) => p.rpm, points);
    final tempSpots = _spots((p) => p.coolantTempC, points);

    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل الرحلة'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'مسح السجل',
            onPressed: points.isEmpty ? null : _clear,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
            onPressed: () => setState(() {}),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'عدد القراءات المسجلة: ${points.length}',
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          _chartCard('السرعة (كم/س)', speedSpots, Colors.blue),
          _chartCard('دورات المحرك (RPM)', rpmSpots, Colors.deepOrange),
          _chartCard('حرارة سائل التبريد (°م)', tempSpots, Colors.teal),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.description_outlined, color: Colors.blueGrey),
              title: const Text('سجل البيانات الكامل (CSV)'),
              subtitle: const Text(
                'كل الحساسات مسجّلة لحظيًا — قابل للتصدير والتحليل خارج التطبيق.',
                style: TextStyle(fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DataLogsScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
