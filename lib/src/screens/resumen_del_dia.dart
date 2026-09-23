import 'package:flutter/material.dart';

import '../api/models.dart';

/// Cómo va el día, en números. Es el mismo bloque que muestra el panel de la web: los seis
/// totales y el detalle por plato. Vive aparte porque lo usan la portada del mesón y la
/// pantalla completa, y porque el día que se agregue un número tiene que aparecer en los dos.
class ResumenDelDia extends StatelessWidget {
  const ResumenDelDia({super.key, required this.dia});

  final DiaDeTrabajo dia;

  @override
  Widget build(BuildContext context) {
    final vivos = dia.tickets.where((t) => t.estado != EstadoTicket.anulado).toList();
    final cupo = dia.opciones.fold<int>(0, (a, o) => a + o.cupo);
    final reservados = dia.opciones.fold<int>(0, (a, o) => a + o.tomados);
    final servidos = vivos.where((t) => t.estado == EstadoTicket.servido).length;
    final llevar = vivos.where((t) => t.paraLlevar).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            // Mismo orden que la web y que el detalle por plato, siguiendo el recorrido del
            // día: cuánto había, cuánto se tomó, cuánto se puede seguir vendiendo, y recién
            // ahí cómo va el servicio.
            _Numero(titulo: 'Cupo', valor: cupo),
            _Numero(titulo: 'Reservados', valor: reservados),
            _Numero(titulo: 'Disponibles', valor: cupo - reservados),
            _Numero(titulo: 'Servidos', valor: servidos, color: const Color(0xFF372B62)),
            _Numero(
                titulo: 'Por servir',
                valor: reservados - servidos,
                color: const Color(0xFFC2410C),
                destacado: true),
            _Numero(titulo: 'Para llevar', valor: llevar, color: const Color(0xFFC2410C)),
          ],
        ),
        const SizedBox(height: 20),
        const Text('Por plato', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 8),
        for (final (n, o) in dia.opciones.indexed)
          _Plato(opcion: o, tickets: vivos, numero: n + 1),
      ],
    );
  }
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
  const _Plato({required this.opcion, required this.tickets, required this.numero});

  final OpcionMenu opcion;
  final List<Ticket> tickets;

  /// Su lugar en la minuta: «opción 1», «opción 2». Es como se piden los platos.
  final int numero;

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
          Row(children: [
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                  color: const Color(0xFF372B62).withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(999)),
              child: Text('OPCIÓN $numero',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w800, color: Color(0xFF372B62))),
            ),
            Expanded(
              child: Text(opcion.nombre,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ]),
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
                _dato('disponibles', opcion.cupo - opcion.tomados),
                _dato('servidos', servidos),
                _dato('por servir', opcion.tomados - servidos),
                // Se muestra aunque sea cero: si aparece y desaparece, el orden deja de ser
                // el mismo en todas las filas y hay que leer las etiquetas cada vez.
                _dato('para llevar', llevar),
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
