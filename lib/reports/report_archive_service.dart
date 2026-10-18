import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/raw_capture.dart';

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
