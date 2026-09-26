import 'package:flutter/material.dart';
import 'screens/scan_screen.dart';

void main() {
  runApp(const RenaultObdApp());
}

class RenaultObdApp extends StatelessWidget {
  const RenaultObdApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'رينو فلوانس OBD2 سكانر',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      theme: ThemeData(
        colorSchemeSeed: Colors.blueGrey,
        useMaterial3: true,
        brightness: Brightness.light,
      ),
      home: const ScanScreen(),
    );
  }
}
