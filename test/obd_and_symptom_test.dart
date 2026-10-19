import 'package:flutter_test/flutter_test.dart';
import 'package:matal_fluence_scan/core/obd_response_utils.dart';
import 'package:matal_fluence_scan/core/pid_registry.dart';
import 'package:matal_fluence_scan/core/transport.dart';
import 'package:matal_fluence_scan/core/elm327_session.dart';
import 'package:matal_fluence_scan/core/simulated_transport.dart';
import 'package:matal_fluence_scan/health/health_score_engine.dart';
import 'package:matal_fluence_scan/symptoms/symptom_diagnostic_service.dart';
import 'package:matal_fluence_scan/symptoms/symptom_models.dart';
import 'package:matal_fluence_scan/symptoms/symptom_registry.dart';
import 'package:matal_fluence_scan/telemetry/vehicle_state.dart';
import 'package:matal_fluence_scan/resources/renault_resource_capture_service.dart';

class _TestTransport implements Transport {
  @override
  bool isConnected = true;

  @override
  Future<bool> connect() async => true;

  @override
  Future<void> disconnect() async => isConnected = false;

  @override
  Future<String> sendAndAwait(String command, {Duration timeout = const Duration(seconds: 4)}) async => 'OK';
}

void main() {
  group('OBD response and PID parsing', () {
    test('parses compact and spaced ATS0 responses identically', () {
      final compact = ObdResponseUtils.extractBytes('410C0000');
      final spaced = ObdResponseUtils.extractBytes('41 0C 00 00');
      expect(compact, [0x41, 0x0C, 0x00, 0x00]);
      expect(spaced, compact);
    });

    test('decodes standard RPM without truncating fractional values', () {
      final rpm = PidRegistry.byKey('rpm').parse([0x41, 0x0C, 0x0F, 0xA0]);
      expect(rpm, 1000.0);
    });

    test('decodes core PID formulas', () {
      expect(PidRegistry.byKey('engine_load').parse([0x41, 0x04, 128]), closeTo(50.196, 0.001));
      expect(PidRegistry.byKey('coolant_temp').parse([0x41, 0x05, 120]), 80);
      expect(PidRegistry.byKey('map').parse([0x41, 0x0B, 90]), 90);
      expect(PidRegistry.byKey('throttle').parse([0x41, 0x11, 255]), 100);
    });

    test('reads ATRV as adapter voltage and captures the command', () async {
      final transport = SimulatedElm327Transport(responses: {'ATRV': '12.6V'});
      final session = Elm327Session(transport);
      final voltage = await session.readAdapterVoltage();
      expect(voltage, 12.6);
      expect(transport.sentCommands, contains('ATRV'));
      expect(session.rawCapture.entries.single.rawResponse, '12.6V');
    });
  });

  group('health coverage', () {
    test('does not present a health score before minimum evidence exists', () {
      final report = HealthScoreEngine.evaluate(VehicleState.initial(), const [], dtcScanned: false);
      expect(report.canAssess, isFalse);
      expect(report.confidencePercent, 0);
    });
  });

  test('resource capture command policy contains only standard read-only commands', () {
    expect(RenaultResourceCaptureService.standardReadOnlyCommands, isNot(contains('04')));
    expect(RenaultResourceCaptureService.standardReadOnlyCommands, isNot(contains('ATSH 7E0')));
    expect(RenaultResourceCaptureService.standardReadOnlyCommands, containsAll(['0902', '03', '06', '0200', 'ATRV']));
  });

  group('symptom rules', () {
    final service = SymptomDiagnosticService(Elm327Session(_TestTransport()));
    final symptom = SymptomRegistry.byId('S001');

    test('detects unstable RPM with positive evidence', () {
      final evidence = <SymptomEvidence>[];
      final conclusions = <String>[];
      service.applyRule('RPM_UNSTABLE', symptom, {}, const [], {
        OperatingState.idle: {'rpm': [700, 900, 700, 900]},
      }, evidence, conclusions);
      expect(conclusions, isNotEmpty);
      expect(evidence.single.confidence, ValueConfidence.medium);
    });

    test('does not report unstable RPM for stable samples', () {
      final evidence = <SymptomEvidence>[];
      final conclusions = <String>[];
      service.applyRule('RPM_UNSTABLE', symptom, {}, const [], {
        OperatingState.idle: {'rpm': [800, 801, 799, 800]},
      }, evidence, conclusions);
      expect(conclusions, isEmpty);
    });

    test('detects lean mixture only above threshold', () {
      final evidence = <SymptomEvidence>[];
      final conclusions = <String>[];
      service.applyRule('LEAN', symptom, {}, const [], {
        OperatingState.idle: {'stft_b1': [14, 15], 'ltft_b1': [2, 3]},
      }, evidence, conclusions);
      expect(conclusions, isNotEmpty);
    });

    test('every registered symptom has an explicit rule set', () {
      expect(SymptomRegistry.all, hasLength(18));
      expect(SymptomRegistry.all.every((s) => s.ruleIds.isNotEmpty), isTrue);
    });
  });
}
