import 'package:flutter/material.dart';
import 'core/obd_connection_controller.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const RenaultObdApp());
}

class RenaultObdApp extends StatefulWidget {
  const RenaultObdApp({super.key});

  @override
  State<RenaultObdApp> createState() => _RenaultObdAppState();
}

class _RenaultObdAppState extends State<RenaultObdApp> {
  final ObdConnectionController _controller = ObdConnectionController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Matal Fluence Scan',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      theme: ThemeData(
        colorSchemeSeed: Colors.blueGrey,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      home: HomeScreen(controller: _controller),
    );
  }
}
