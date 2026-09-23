import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import 'resumen_del_dia.dart';

/// Cómo va el día, en números. La misma pantalla que la pestaña «En vivo» del panel: los
/// mismos seis números y la misma tabla, para que quien mira las dos en el mismo turno no
/// tenga que traducir nada.
///
/// Se refresca sola cada diez segundos mientras está abierta. En la fila, un número viejo es
/// peor que ningún número: alguien decide con él si le quedan porciones.
class VivoScreen extends StatefulWidget {
  const VivoScreen({super.key, required this.estado});

  final AppState estado;

  @override
  State<VivoScreen> createState() => _VivoScreenState();
}

class _VivoScreenState extends State<VivoScreen> {
  Timer? _latido;
  DateTime? _ultimo;

  @override
  void initState() {
    super.initState();
    _refrescar();
    _latido = Timer.periodic(const Duration(seconds: 10), (_) => _refrescar());
  }

  @override
  void dispose() {
    _latido?.cancel();
    super.dispose();
  }

  Future<void> _refrescar() async {
    await widget.estado.refrescar(silencioso: true);
    if (!mounted) return;
    setState(() => _ultimo = DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final dia = widget.estado.dia;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cómo va el día'),
        actions: [
          IconButton(onPressed: _refrescar, icon: const Icon(Icons.refresh), tooltip: 'Actualizar'),
        ],
      ),
      body: dia == null
          ? const Center(child: Text('Todavía no se ha bajado el día'))
          : RefreshIndicator(
              onRefresh: _refrescar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('${dia.fecha} · ${dia.unidad}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(
                    _ultimo == null
                        ? 'actualizando…'
                        : 'al día a las ${_hora(_ultimo!)} · se actualiza sola',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  ResumenDelDia(dia: dia),
                ],
              ),
            ),
    );
  }

  static String _hora(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}

