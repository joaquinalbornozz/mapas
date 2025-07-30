import 'package:flutter/material.dart';
//import 'package:mapas/pages/map_page.dart';
import 'package:mapas/pages/mapsms_page.dart';
import 'package:mapas/services/background_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Flutter Map Demo', home: MapSmsRutaPage());
  }
}
