import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../reports/report_archive_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _archive = ReportArchiveService.instance;
  String? _folder;
  bool _enabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final folder = await _archive.selectedFolder;
    final enabled = await _archive.autoExportEnabled;
    if (mounted) setState(() { _folder = folder; _enabled = enabled; _loading = false; });
  }

  Future<void> _chooseFolder() async {
    final path = await FilePicker.platform.getDirectoryPath(dialogTitle: 'اختر مجلد حفظ التقارير');
    if (path == null || path.isEmpty) return;
    await _archive.setSelectedFolder(path);
    if (mounted) setState(() => _folder = path);
  }

  Future<void> _setEnabled(bool value) async {
    await _archive.setAutoExportEnabled(value);
    if (mounted) setState(() => _enabled = value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات التطبيق')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text('حفظ التقارير', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('الحفظ التلقائي عند قطع الاتصال'),
                  subtitle: const Text('يحفظ Raw Capture وCSV وتقارير الفحص في جلسة واحدة'),
                  value: _enabled,
                  onChanged: _setEnabled,
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('مجلد التقارير'),
                  subtitle: Text(_folder == null ? 'لم يتم اختيار مجلد خارجي' : _folder!, maxLines: 3, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(icon: const Icon(Icons.folder_open), tooltip: 'اختيار مجلد', onPressed: _chooseFolder),
                ),
                if (_folder != null)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: TextButton.icon(
                      onPressed: () async { await _archive.setSelectedFolder(null); if (mounted) setState(() => _folder = null); },
                      icon: const Icon(Icons.clear),
                      label: const Text('إزالة المجلد المختار'),
                    ),
                  ),
                const SizedBox(height: 12),
                const Text('عند انقطاع الاتصال، ينشئ التطبيق مجلدًا باسم الجلسة ويضع داخله التقارير المتوفرة وملف CSV وRaw Capture. إذا تعذر الوصول للمجلد، يحتفظ بنسخة داخلية.', style: TextStyle(color: Colors.grey)),
              ],
            ),
    );
  }
}
