import '../core/elm327_session.dart';
import '../core/obd_response_utils.dart';

class Mode06Result {
  final String raw;
  final List<int> bytes;
  final String status;
  const Mode06Result({required this.raw, required this.bytes, required this.status});
  Map<String, Object?> toJson() => {'raw': raw, 'bytes': bytes, 'status': status};
}

/// Generic Mode 06 capture. MID/TID meanings remain unconfirmed because they
/// vary by ECU; this class deliberately preserves raw evidence.
class Mode06Reader {
  final Elm327Session session;
  Mode06Reader(this.session);
  Future<Mode06Result> read() async {
    final raw = await session.readMode06Raw();
    final bytes = ObdResponseUtils.extractBytes(raw);
    return Mode06Result(raw: raw, bytes: bytes, status: bytes.isEmpty ? 'unavailable' : 'raw_only_unconfirmed');
  }
}
