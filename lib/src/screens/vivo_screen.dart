import 'dart:async';

import 'package:flutter/material.dart';

import '../api/models.dart';
import '../app_state.dart';

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
    final tickets = (dia?.tickets ?? []).where((t) => t.estado != EstadoTicket.anulado).toList();

    final cupo = (dia?.opciones ?? []).fold<int>(0, (a, o) => a + o.cupo);
    final reservados = (dia?.opciones ?? []).fold<int>(0, (a, o) => a + o.tomados);
    final servidos = tickets.where((t) => t.estado == EstadoTicket.servido).length;
    final llevar = tickets.where((t) => t.paraLlevar).length;

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

                  // Los seis números, en el mismo orden que en el panel.
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _Numero(titulo: 'Cupo', valor: cupo),
                      _Numero(titulo: 'Reservados', valor: reservados),
                      _Numero(titulo: 'Servidos', valor: servidos, color: const Color(0xFF3B2D52)),
                      _Numero(
                          titulo: 'Por servir',
                          valor: reservados - servidos,
                          color: const Color(0xFFC2410C),
                          destacado: true),
                      _Numero(titulo: 'Para llevar', valor: llevar, color: const Color(0xFFC2410C)),
                      _Numero(titulo: 'Quedan', valor: cupo - reservados),
                    ],
                  ),

                  const SizedBox(height: 22),
                  const Text('Por plato',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  const SizedBox(height: 8),

                  for (final o in dia.opciones) _Plato(opcion: o, tickets: tickets),
                ],
              ),
            ),
    );
  }

  static String _hora(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:'
      '${t.second.toString().padLeft(2, '0')}';
}

class _Numero extends StatelessWidget {
  const _Numero(
      {required this.titulo, required this.valor, this.color, this.destacado = false});

  final String titulo;
  final int valor;
  final Color? color;
  final bool destacado;

  @override
  Widget build(BuildContext context) => Container(
        width: 108,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(
              color: destacado ? (color ?? const Color(0xFFE4E1EA)) : const Color(0xFFE4E1EA),
              width: destacado ? 2 : 1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo.toUpperCase(),
                style: const TextStyle(fontSize: 10, letterSpacing: 1, color: Colors.black54)),
            Text('$valor',
                style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w700, color: color ?? Colors.black87)),
          ],
        ),
      );
}

class _Plato extends StatelessWidget {
  const _Plato({required this.opcion, required this.tickets});

  final OpcionMenu opcion;
  final List<Ticket> tickets;

  @override
  Widget build(BuildContext context) {
    final suyos = tickets.where((t) => t.opcion == opcion.nombre).toList();
    final servidos = suyos.where((t) => t.estado == EstadoTicket.servido).length;
    final llevar = suyos.where((t) => t.paraLlevar).length;
    final proporcion = opcion.cupo == 0 ? 0.0 : opcion.tomados / opcion.cupo;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE4E1EA)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(opcion.nombre, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: proporcion.clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: const Color(0xFFEFEDF3),
              color: proporcion >= 1 ? const Color(0xFFC2410C) : const Color(0xFF3B2D52),
            ),
          ),
          const SizedBox(height: 8),
          DefaultTextStyle(
            style: const TextStyle(fontSize: 13, color: Colors.black87),
            child: Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _dato('cupo', opcion.cupo),
                _dato('reservados', opcion.tomados),
                _dato('servidos', servidos),
                _dato('por servir', opcion.tomados - servidos),
                if (llevar > 0) _dato('para llevar', llevar),
                _dato('quedan', opcion.cupo - opcion.tomados),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dato(String titulo, int valor) => RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 13, color: Colors.black54),
          children: [
            TextSpan(
                text: '$valor ',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15, color: Colors.black87)),
            TextSpan(text: titulo),
          ],
        ),
      );
}
