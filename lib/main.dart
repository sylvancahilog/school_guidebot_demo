import 'package:flutter/material.dart';
import 'package:flutter_edge_ai/flutter_edge_ai.dart';
import 'package:flutter_edge_ai_litertlm/flutter_edge_ai_litertlm.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FlutterEdgeAi.initialize(
    inferenceEngines: const [LiteRtLmEngine()],
  );
  runApp(const SchoolGuidebotApp());
}

/*
 * The root widget that sets up the app's theme and launches the home screen.
 * It also initializes the AI inference engine once at startup before any
 * screen is shown, so the rest of the app can use it right away.
 */
class SchoolGuidebotApp extends StatelessWidget {
  const SchoolGuidebotApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'School Guide',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
