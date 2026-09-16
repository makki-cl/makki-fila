import 'package:flutter/material.dart';

import '../api/models.dart';
import '../app_state.dart';

/// La lista del día, para quien llega sin QR: los que se anotaron por el enlace general se
/// buscan por nombre y se marcan a mano.
///
/// La gente de empresas **acreditadas** no aparece acá a propósito: ellos llegan con QR, y
/// tenerlos en una lista que se marca con un toque invitaba justamente a saltarse el QR. Si a
/// alguno se le apagó el teléfono, el camino es dictar su código en el lector.
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
    final acreditados = (dia?.tickets ?? []).where((t) => t.acreditada).length;
    final tickets = (dia?.tickets ?? []).where((t) {
      if (t.acreditada) return false;
      if (t.estado == EstadoTicket.anulado) return false;
      if (_soloPendientes && t.estado == EstadoTicket.servido) return false;
      if (_busqueda.isEmpty) return true;
      final q = _busqueda.toLowerCase();
      return t.persona.toLowerCase().contains(q) ||
          t.codigo.toLowerCase().contains(q) ||
          (t.empresa?.toLowerCase().contains(q) ?? false);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lista de anotados'),
        actions: [
          // Las marcas hechas a mano sin señal quedan acá igual que las del lector: el botón
          // tiene que estar donde se marcó, no solo en la pantalla de inicio.
          if (widget.estado.pendientes > 0)
            TextButton.icon(
              onPressed: () async {
                final n = await widget.estado.sincronizar();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(n > 0 ? '$n marca(s) enviadas' : 'Sigue sin conexión'),
                ));
                setState(() {});
              },
              icon: const Icon(Icons.cloud_upload, color: Colors.white),
              label: Text('${widget.estado.pendientes}',
                  style: const TextStyle(color: Colors.white)),
            ),
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () async {
              await widget.estado.refrescar();
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
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
          if (acreditados > 0)
            Container(
              width: double.infinity,
              color: const Color(0xFFFDF6E7),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(
                '$acreditados ticket(s) de empresas acreditadas no salen acá: llegan con QR. '
                'Si a alguien se le apagó el teléfono, dicta su código en el lector.',
                style: const TextStyle(fontSize: 12),
              ),
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
        content: const Text('Marcar como servido sin escanear el QR.'),
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
        ResultadoMarca.fueraDeLaCopia => 'No está en la lista bajada; actualiza',
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
