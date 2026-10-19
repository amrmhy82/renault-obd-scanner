import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/raw_capture.dart';
import '../core/pid_registry.dart';

/// Stores reports during a connection session and exports the complete bundle
/// when the session ends. The internal copy protects reports from picker or
/// storage permission failures.
class ReportArchiveService {
  ReportArchiveService._();
  static final instance = ReportArchiveService._();

  static const _folderKey = 'report_archive_folder_v1';
  static const _enabledKey = 'report_archive_auto_enabled_v1';
  String? _sessionId;
  Directory? _sessionDir;
  final List<File> _sessionFiles = [];

  Future<String?> get selectedFolder async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_folderKey);
  }

  Future<void> setSelectedFolder(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null || path.trim().isEmpty) {
      await prefs.remove(_folderKey);
    } else {
      await prefs.setString(_folderKey, path);
    }
  }

  Future<bool> get autoExportEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  Future<void> setAutoExportEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
  }

  Future<void> beginSession() async {
    _sessionId = _timestamp();
    final base = await getApplicationDocumentsDirectory();
    _sessionDir = Directory('${base.path}/obd_report_archive/$_sessionId');
    await _sessionDir!.create(recursive: true);
    _sessionFiles.clear();
  }

  Future<File?> recordJson(String type, Map<String, Object?> data) async {
    if (_sessionDir == null) await beginSession();
    final file = File('${_sessionDir!.path}/${type}_${_timestamp()}.json');
    try {
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data), flush: true);
      _sessionFiles.add(file);
      return file;
    } catch (_) {
      return null;
    }
  }

  /// Writes a stable checkpoint so a cable/app failure does not erase the
  /// resource evidence collected before the failure.
  Future<File?> writePartialJson(String type, Map<String, Object?> data) async {
    if (_sessionDir == null) await beginSession();
    final file = File('${_sessionDir!.path}/$type.partial.json');
    try {
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data), flush: true);
      if (!_sessionFiles.contains(file)) _sessionFiles.add(file);
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<void> removePartialJson(String type) async {
    final file = File('${_sessionDir?.path}/$type.partial.json');
    try {
      if (await file.exists()) await file.delete();
      _sessionFiles.removeWhere((candidate) => candidate.path == file.path);
    } catch (_) {}
  }

  Future<ReportExportResult> finalizeSession({required String rawCaptureJson, File? csvFile}) async {
    if (_sessionDir == null) await beginSession();
    final rawFile = File('${_sessionDir!.path}/obd_raw_capture_${_sessionId ?? _timestamp()}.json');
    try {
      await rawFile.writeAsString(rawCaptureJson, flush: true);
      if (!_sessionFiles.contains(rawFile)) _sessionFiles.add(rawFile);
    } catch (_) {}
    if (csvFile != null && await csvFile.exists() && !_sessionFiles.contains(csvFile)) {
      _sessionFiles.add(csvFile);
    }
    await _writeSessionSummary(rawCaptureJson, csvFile);

    final folder = await selectedFolder;
    if (!(await autoExportEnabled) || folder == null || folder.trim().isEmpty) {
      return ReportExportResult(success: false, destination: null, files: List<File>.unmodifiable(_sessionFiles), message: 'لم يتم اختيار مجلد حفظ خارجي؛ تم الاحتفاظ بنسخة داخل التطبيق');
    }
    final destination = Directory(folder);
    try {
      await destination.create(recursive: true);
      final sessionDestination = Directory('${destination.path}/obd_session_${_sessionId ?? _timestamp()}');
      await sessionDestination.create(recursive: true);
      final copied = <File>[];
      for (final file in _sessionFiles) {
        if (!await file.exists()) continue;
        final target = File('${sessionDestination.path}/${file.uri.pathSegments.last}');
        await file.copy(target.path);
        copied.add(target);
      }
      return ReportExportResult(success: true, destination: sessionDestination.path, files: copied, message: 'تم حفظ تقارير الجلسة في المجلد المختار');
    } catch (error) {
      return ReportExportResult(success: false, destination: destination.path, files: List<File>.unmodifiable(_sessionFiles), message: 'تعذر النسخ إلى المجلد المختار: $error');
    }
  }

  Future<void> _writeSessionSummary(String rawCaptureJson, File? csvFile) async {
    if (_sessionDir == null) return;
    final summary = <String, Object?>{
      'sessionId': _sessionId,
      'generatedAt': DateTime.now().toIso8601String(),
      'source': 'application_session_archive',
    };
    if (csvFile != null && await csvFile.exists()) {
      final csv = await _analyzeCsv(csvFile);
      summary['csv'] = csv;
    } else {
      summary['csv'] = {'available': false, 'reason': 'لم يتم إنشاء ملف CSV'};
    }
    try {
      final raw = jsonDecode(rawCaptureJson);
      final entries = raw is List ? raw : const [];
      final errors = entries.whereType<Map>().where((e) => e['error'] == true).length;
      final commands = <String, int>{};
      for (final entry in entries.whereType<Map>()) {
        final command = entry['request']?.toString();
        if (command == null) continue;
        commands[command] = (commands[command] ?? 0) + 1;
      }
      summary['rawCapture'] = {
        'entries': entries.length,
        'errors': errors,
        'errorRatePercent': entries.isEmpty ? 0 : (errors * 100 / entries.length).roundToDouble(),
        'commands': commands,
      };
    } catch (_) {
      summary['rawCapture'] = {'available': false, 'reason': 'تعذر تحليل Raw Capture'};
    }
    try {
      final file = File('${_sessionDir!.path}/session_summary.json');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(summary), flush: true);
      _sessionFiles.add(file);
    } catch (_) {}
  }

  Future<Map<String, Object?>> _analyzeCsv(File file) async {
    final lines = await file.readAsLines();
    if (lines.length < 2) return {'available': false, 'reason': 'لا توجد صفوف كافية'};
    final header = lines.first.replaceFirst('\uFEFF', '').split(',');
    final columns = <String, List<double>>{};
    for (final pid in PidRegistry.all) {
      columns[pid.key] = <double>[];
    }
    int? firstMs;
    int? lastMs;
    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty) continue;
      final cells = line.split(',');
      if (cells.length < header.length) continue;
      final elapsed = int.tryParse(cells[1]);
      if (elapsed != null) {
        firstMs ??= elapsed;
        lastMs = elapsed;
      }
      for (var i = 2; i < header.length && i < cells.length; i++) {
        final key = header[i];
        final value = double.tryParse(cells[i]);
        if (value != null && columns.containsKey(key)) columns[key]!.add(value);
      }
    }
    final observed = <String, Object?>{};
    final missing = <String>[];
    for (final pid in PidRegistry.all) {
      final values = columns[pid.key]!;
      if (values.isEmpty) {
        missing.add(pid.key);
        continue;
      }
      var min = values.first;
      var max = values.first;
      var sum = 0.0;
      for (final value in values) {
        if (value < min) min = value;
        if (value > max) max = value;
        sum += value;
      }
      observed[pid.key] = {
        'nameAr': pid.nameAr,
        'samples': values.length,
        'min': double.parse(min.toStringAsFixed(3)),
        'max': double.parse(max.toStringAsFixed(3)),
        'average': double.parse((sum / values.length).toStringAsFixed(3)),
      };
    }
    return {
      'available': true,
      'rows': lines.length - 1,
      'durationMs': firstMs == null || lastMs == null ? null : lastMs! - firstMs!,
      'observedPids': observed,
      'missingPids': missing,
    };
  }

  Future<void> resetSession() async {
    _sessionId = null;
    _sessionDir = null;
    _sessionFiles.clear();
  }

  String _timestamp() => DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
}

class ReportExportResult {
  final bool success;
  final String? destination;
  final List<File> files;
  final String message;
  const ReportExportResult({required this.success, required this.destination, required this.files, required this.message});
}

extension RawCaptureArchive on RawCaptureStore {
  String get archiveJson => toJson();
}
