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
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9E1B15),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF8F8F8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF3A1715),
          elevation: 0,
          centerTitle: false,
        ),
        cardTheme: CardTheme(
          color: Colors.white,
          elevation: 1,
          shadowColor: const Color(0x33000000),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.symmetric(vertical: 5),
        ),
        dividerTheme: const DividerThemeData(color: Color(0xFFE8DEDD)),
      ),
      home: HomeScreen(controller: _controller),
    );
  }
}
