import 'package:flutter/material.dart';

import '../api/models.dart';
import '../app_state.dart';

/// La lista del día, para quien llega sin QR: los que se anotaron por el enlace general se
/// buscan por nombre y se marcan a mano. Los de empresas acreditadas salen con su etiqueta,
/// porque a ellos se les debe pedir el QR.
class ListScreen extends StatefulWidget {
  const ListScreen({super.key, required this.estado});

  final AppState estado;

  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  String _busqueda = '';
  bool _soloPendientes = true;

  @override
  Widget build(BuildContext context) {
    final dia = widget.estado.dia;
    final tickets = (dia?.tickets ?? []).where((t) {
      if (t.estado == EstadoTicket.anulado) return false;
      if (_soloPendientes && t.estado == EstadoTicket.servido) return false;
      if (_busqueda.isEmpty) return true;
      final q = _busqueda.toLowerCase();
      return t.persona.toLowerCase().contains(q) ||
          t.codigo.toLowerCase().contains(q) ||
          (t.empresa?.toLowerCase().contains(q) ?? false);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Lista de anotados')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              autofocus: true,
              onChanged: (v) => setState(() => _busqueda = v),
              decoration: const InputDecoration(
                hintText: 'Buscar por nombre, empresa o código',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          SwitchListTile(
            value: _soloPendientes,
            onChanged: (v) => setState(() => _soloPendientes = v),
            title: const Text('Mostrar solo los que faltan'),
            dense: true,
          ),
          const Divider(height: 1),
          Expanded(
            child: tickets.isEmpty
                ? const Center(child: Text('Nadie calza con la búsqueda'))
                : ListView.separated(
                    itemCount: tickets.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) => _Fila(
                      ticket: tickets[i],
                      onMarcar: () => _marcar(tickets[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _marcar(Ticket t) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.persona),
        content: Text(t.acreditada
            ? '${t.empresa} es una empresa acreditada: su gente debería llegar con QR. '
                '¿Marcar igual sin escanear?'
            : 'Marcar como servido sin escanear el QR.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Marcar')),
        ],
      ),
    );
    if (confirmado != true) return;

    final (resultado, _) = await widget.estado.marcar(t.token.isNotEmpty ? t.token : t.codigo);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(switch (resultado) {
        ResultadoMarca.ok => '${t.persona}: servido',
        ResultadoMarca.yaConsumido => '${t.persona} ya estaba servido',
        ResultadoMarca.anulado => 'Ese ticket está anulado',
        _ => 'No se pudo marcar',
      }),
    ));
    setState(() {});
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.ticket, required this.onMarcar});

  final Ticket ticket;
  final VoidCallback onMarcar;

  @override
  Widget build(BuildContext context) {
    final servido = ticket.estado == EstadoTicket.servido;
    return ListTile(
      title: Row(children: [
        Expanded(
          child: Text(ticket.persona,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  decoration: servido ? TextDecoration.lineThrough : null)),
        ),
        if (ticket.acreditada)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
                color: const Color(0xFF146C4E).withValues(alpha: .12),
                borderRadius: BorderRadius.circular(999)),
            child: const Text('con QR',
                style: TextStyle(fontSize: 11, color: Color(0xFF146C4E))),
          ),
      ]),
      subtitle: Text([
        ticket.codigoLegible,
        ticket.opcion,
        if (ticket.empresa != null) ticket.empresa!,
        if (ticket.area != null && ticket.area!.isNotEmpty) ticket.area!,
      ].join(' · ')),
      trailing: servido
          ? const Icon(Icons.check_circle, color: Color(0xFF146C4E))
          : FilledButton(onPressed: onMarcar, child: const Text('Marcar')),
    );
  }
}
