import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/verify_capture_schema.dart <capture.json>');
    exitCode = 64;
    return;
  }
  final file = File(args.single);
  if (!await file.exists()) {
    stderr.writeln('Capture file not found: ${args.single}');
    exitCode = 2;
    return;
  }
  final decoded = jsonDecode(await file.readAsString());
  if (decoded is! Map) return _fail('root must be an object');
  final required = ['captureVersion', 'capturedAt', 'status', 'safety', 'adapter',
    'protocolBefore', 'protocolAfter', 'vehicle', 'supportedPids', 'dtcs',
    'readinessBytes', 'mode06', 'freezeFrame', 'rawCapture'];
  final missing = required.where((key) => !decoded.containsKey(key)).toList();
  if (missing.isNotEmpty) return _fail('missing keys: ${missing.join(', ')}');
  final safety = decoded['safety'];
  if (safety is! Map || safety['readOnly'] != true || safety['arbitraryCanProbing'] != false) {
    return _fail('capture must be explicitly read-only and must not probe arbitrary CAN IDs');
  }
  if (decoded['rawCapture'] is! List || decoded['supportedPids'] is! List) {
    return _fail('rawCapture and supportedPids must be arrays');
  }
  stdout.writeln('capture schema ok: ${decoded['captureVersion']} (${decoded['status']})');
}

Never _fail(String message) {
  stderr.writeln('capture schema invalid: $message');
  exit(1);
}
