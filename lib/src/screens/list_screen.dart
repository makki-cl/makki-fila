import 'package:flutter/material.dart';

import '../api/models.dart';
import '../app_state.dart';
import '../orden.dart';

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

/// Qué parte de la lista se está mirando.
enum FiltroLista { porServir, servidos, anulados, todos }

class _ListScreenState extends State<ListScreen> {
  String _busqueda = '';

  // Arranca en «por servir» todos los días: es lo que se mira mientras hay fila. Ver a los
  // servidos es para después —cuadrar, buscar a alguien que dice que no pasó— y para eso se
  // elige a propósito.
  FiltroLista _filtro = FiltroLista.porServir;

  @override
  Widget build(BuildContext context) {
    final dia = widget.estado.dia;
    final acreditados = (dia?.tickets ?? []).where((t) => t.acreditada).length;

    // La base: todos los del enlace, anulados incluidos. Sobre esta se cuentan los botones,
    // para que el número no dependa de lo que haya escrito en el buscador.
    final base = (dia?.tickets ?? []).where((t) => !t.acreditada).toList();
    final servidos = base.where((t) => t.estado == EstadoTicket.servido).length;
    final anulados = base.where((t) => t.estado == EstadoTicket.anulado).length;
    final porServir = base.length - servidos - anulados;

    final tickets = base.where((t) {
      final servido = t.estado == EstadoTicket.servido;
      final anulado = t.estado == EstadoTicket.anulado;
      // Los anulados solo aparecen cuando se piden: no tienen nada que hacer en la lista con
      // la que se atiende, y confundirlos con un pendiente es servir un almuerzo de más.
      if (_filtro != FiltroLista.anulados && anulado) return false;
      if (_filtro == FiltroLista.porServir && servido) return false;
      if (_filtro == FiltroLista.servidos && !servido) return false;
      if (_filtro == FiltroLista.anulados && !anulado) return false;
      if (_busqueda.isEmpty) return true;
      final q = _busqueda.toLowerCase();
      return t.persona.toLowerCase().contains(q) ||
          t.codigo.toLowerCase().contains(q) ||
          (t.empresa?.toLowerCase().contains(q) ?? false);
    }).toList();

    final filas = ordenar(tickets, widget.estado.orden);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lista de anotados'),
        actions: [
          // Las marcas hechas a mano sin señal quedan acá igual que las del lector: el botón
          // tiene que estar donde se marcó, no solo en la pantalla de inicio.
          if (widget.estado.pendientes > 0)
            TextButton.icon(
              onPressed: () async {
                final r = await widget.estado.sincronizar();
                if (!context.mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(mensajeDeSincronia(r))));
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SegmentedButton<OrdenLista>(
              // Sin íconos: con tres opciones y los nombres completos, en la tablet del mesón
              // se lee mejor el texto solo.
              segments: const [
                ButtonSegment(value: OrdenLista.alfabetico, label: Text('Alfabético')),
                ButtonSegment(value: OrdenLista.empresa, label: Text('Por empresa')),
                ButtonSegment(value: OrdenLista.cronologico, label: Text('Cronológico')),
              ],
              selected: {widget.estado.orden},
              onSelectionChanged: (o) async {
                await widget.estado.cambiarOrden(o.first);
                if (mounted) setState(() {});
              },
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SegmentedButton<FiltroLista>(
              segments: [
                ButtonSegment(
                  value: FiltroLista.porServir,
                  label: Text('Por servir ($porServir)'),
                ),
                ButtonSegment(
                  value: FiltroLista.servidos,
                  label: Text('Servidos ($servidos)'),
                ),
                ButtonSegment(
                  value: FiltroLista.anulados,
                  label: Text('Anulados ($anulados)'),
                ),
                ButtonSegment(
                  value: FiltroLista.todos,
                  label: Text('Todos (${base.length - anulados})'),
                ),
              ],
              selected: {_filtro},
              onSelectionChanged: (f) => setState(() => _filtro = f.first),
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
            ),
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
            child: filas.isEmpty
                ? Center(child: Text(_vacio()))
                : ListView.builder(
                    itemCount: filas.length,
                    itemBuilder: (context, i) {
                      final fila = filas[i];
                      if (fila is GrupoDeEmpresa) return _Encabezado(grupo: fila);
                      final t = fila as Ticket;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (i > 0 && filas[i - 1] is Ticket) const Divider(height: 1),
                          _Fila(ticket: t, onMarcar: () => _marcar(t)),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Qué decir cuando no hay nada que mostrar. «Nadie calza con la búsqueda» sobre una
  /// lista de servidos vacía hace pensar que se perdieron los datos.
  String _vacio() {
    if (_busqueda.isNotEmpty) return 'Nadie calza con la búsqueda';
    return switch (_filtro) {
      FiltroLista.porServir => 'No queda nadie por servir',
      FiltroLista.servidos => 'Todavía no se ha servido a nadie',
      FiltroLista.anulados => 'Nadie ha anulado hoy',
      FiltroLista.todos => 'No hay nadie anotado por el enlace',
    };
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

    final resultado =
        (await widget.estado.marcar(t.token.isNotEmpty ? t.token : t.codigo)).resultado;
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(switch (resultado) {
        ResultadoMarca.ok => '${t.persona}: servido',
        ResultadoMarca.yaConsumido => '${t.persona} ya estaba servido',
        ResultadoMarca.anulado => 'Ese ticket está anulado',
        ResultadoMarca.fueraDeLaCopia => 'No está en la lista bajada; actualiza',
        ResultadoMarca.desactivado => '${t.persona} está desactivado por su empresa',
        ResultadoMarca.valeCobrado => '${t.persona}: vale cobrado',
        ResultadoMarca.valeYaUsado => 'Ese vale ya se usó',
        ResultadoMarca.valeReservado => '${t.persona} tiene almuerzo reservado con ese ticket',
        ResultadoMarca.sinTicket => '${t.persona} está anotado pero sin ticket',
        ResultadoMarca.vencido => 'Ese ticket está vencido',
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
    final anulado = ticket.estado == EstadoTicket.anulado;
    return ListTile(
      title: Row(children: [
        // Para llevar va antes que el nombre: es lo que cambia lo que hace el mesón con el
        // plato, y tiene que verse sin leer la fila entera.
        if (ticket.paraLlevar)
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: const Color(0xFFC2410C).withValues(alpha: .14),
                borderRadius: BorderRadius.circular(999)),
            child: const Text('PARA LLEVAR',
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFC2410C))),
          ),
        Expanded(
          child: Text(ticket.persona,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: anulado ? Colors.black45 : null,
                  decoration:
                      servido || anulado ? TextDecoration.lineThrough : null)),
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
        // La hora de quien ya pasó: es lo primero que se pregunta cuando alguien dice que no
        // lo atendieron.
        if (servido && ticket.consumidoUtc != null) 'servido ${_hora(ticket.consumidoUtc!)}',
        if (anulado)
          ticket.anuladoUtc != null ? 'ANULADO ${_hora(ticket.anuladoUtc!)}' : 'ANULADO',
      ].join(' · ')
          // Lo que la persona escribió al anotarse: alergias, sin ají, doble arroz. De nada
          // sirve guardarlo si quien sirve el plato no lo ve.
          +
          (ticket.comentario == null || ticket.comentario!.isEmpty
              ? ''
              : '\n«${ticket.comentario}»')),
      isThreeLine: ticket.comentario != null && ticket.comentario!.isNotEmpty,
      trailing: anulado
          // Un anulado no se sirve: no hay botón que apretar, solo el rastro de que existió.
          ? const Icon(Icons.cancel, color: Color(0xFFC0392B))
          : servido
              ? const Icon(Icons.check_circle, color: Color(0xFF146C4E))
              : FilledButton(onPressed: onMarcar, child: const Text('Marcar')),
    );
  }
}


/// Encabezado del grupo de una empresa. Dice cuántos son, que es lo que pregunta quien pasa
/// lista por empresa antes de contar cabezas.
class _Encabezado extends StatelessWidget {
  const _Encabezado({required this.grupo});

  final GrupoDeEmpresa grupo;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: const Color(0xFFEDF0EA),
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(grupo.empresa,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Text('${grupo.cuantos}',
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
          ],
        ),
      );
}

/// Hora local del equipo: el servidor guarda en UTC y el mesón piensa en hora de Chile.
String _hora(DateTime utc) {
  final l = utc.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}
