import 'package:flutter/material.dart';

import '../app_state.dart';

/// Primera pantalla: se autoriza el equipo con el código que entrega el panel. Pasa una sola
/// vez en la vida del aparato.
class EnrollScreen extends StatefulWidget {
  const EnrollScreen({super.key, required this.estado});

  final AppState estado;

  @override
  State<EnrollScreen> createState() => _EnrollScreenState();
}

class _EnrollScreenState extends State<EnrollScreen> {
  // Dirección por defecto: hoy el sistema se alcanza por IP, sin dominio ni certificado.
  // Cuando dev.makki.cl resuelva, cambiar por https://dev.makki.cl.
  final _url = TextEditingController(text: 'http://38.7.207.23');
  final _codigo = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    _codigo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final estado = widget.estado;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('MAKKI',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 5,
                        color: Color(0xFF123528))),
                const SizedBox(height: 4),
                const Text('Lector de tickets del mesón',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.black54)),
                const SizedBox(height: 32),
                TextField(
                  controller: _url,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
                      labelText: 'Dirección del sistema', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _codigo,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(fontSize: 24, letterSpacing: 4, fontFamily: 'monospace'),
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(
                    labelText: 'Código de enrolamiento',
                    helperText: 'Lo entrega el panel, en Equipos de la fila',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 22),
                if (estado.error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(estado.error!,
                        textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
                  ),
                FilledButton(
                  onPressed: estado.cargando
                      ? null
                      : () => estado.enrolar(_url.text, _codigo.text, 'Android'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                  child: estado.cargando
                      ? const SizedBox(
                          height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Autorizar este equipo', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
