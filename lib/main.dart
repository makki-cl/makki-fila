import 'package:flutter/material.dart';

import 'src/app_state.dart';
import 'src/data/local_store.dart';
import 'src/screens/enroll_screen.dart';
import 'src/screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MakkiFilaApp());
}

/// Paleta de Makki, la misma del panel: morado profundo de chrome y el Pantone 276C
/// del manual de marca.
///
/// El verde no desaparece: sigue siendo el «puede pasar» del lector. En una pantalla que
/// decide si alguien almuerza, el visto bueno tiene que ser verde aunque la marca sea morada.
const _ink = Color(0xFF291F47);
const _morado = Color(0xFF372B62);  // Pantone 276C

class MakkiFilaApp extends StatefulWidget {
  const MakkiFilaApp({super.key});

  @override
  State<MakkiFilaApp> createState() => _MakkiFilaAppState();
}

class _MakkiFilaAppState extends State<MakkiFilaApp> {
  final AppState _estado = AppState(LocalStore());

  @override
  void initState() {
    super.initState();
    _estado.iniciar();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Makki · Fila',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: _morado, primary: _morado),
        appBarTheme: const AppBarTheme(backgroundColor: _ink, foregroundColor: Colors.white),
        scaffoldBackgroundColor: const Color(0xFFF6F7F4),
      ),
      home: AnimatedBuilder(
        animation: _estado,
        builder: (context, _) =>
            _estado.enrolado ? HomeScreen(estado: _estado) : EnrollScreen(estado: _estado),
      ),
    );
  }
}
