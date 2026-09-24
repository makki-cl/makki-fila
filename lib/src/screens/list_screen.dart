import 'package:flutter/material.dart';

import '../api/models.dart';
import '../app_state.dart';
import '../orden.dart';
import 'anotar_screen.dart';

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
enum FiltroLista {
  porServir,
  servidos,
  noCancelados,
  paraLlevar,
  anulados,
  todos
}

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
    final noCancelados =
        base.where((t) => t.estado == EstadoTicket.noCancelado).length;
    final llevar = base
        .where((t) => t.paraLlevar && t.estado != EstadoTicket.anulado)
        .length;
    final porServir = base.length - servidos - anulados - noCancelados;

    final tickets = base.where((t) {
      final servido = t.estado == EstadoTicket.servido;
      final anulado = t.estado == EstadoTicket.anulado;
      final noCancelado = t.estado == EstadoTicket.noCancelado;
      // Los anulados solo aparecen cuando se piden: no tienen nada que hacer en la lista con
      // la que se atiende, y confundirlos con un pendiente es servir un almuerzo de más.
      if (_filtro != FiltroLista.anulados && anulado) return false;
      // El no cancelado tampoco es un pendiente: el día en que se cerró ya no llegó.
      if (_filtro == FiltroLista.porServir && (servido || noCancelado)) {
        return false;
      }
      if (_filtro == FiltroLista.servidos && !servido) return false;
      if (_filtro == FiltroLista.noCancelados && !noCancelado) return false;
      if (_filtro == FiltroLista.anulados && !anulado) return false;
      // La cocina prepara los envases aparte: poder ver solo esos es media pantalla de trabajo.
      if (_filtro == FiltroLista.paraLlevar && !t.paraLlevar) return false;
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
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(mensajeDeSincronia(r))));
                setState(() {});
              },
              icon: const Icon(Icons.cloud_upload, color: Colors.white),
              label: Text('${widget.estado.pendientes}',
                  style: const TextStyle(color: Colors.white)),
            ),
          IconButton(
            tooltip: 'Anotar comensal',
            onPressed: () async {
              await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AnotarScreen(estado: widget.estado)));
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.person_add),
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
                ButtonSegment(
                    value: OrdenLista.alfabetico, label: Text('Alfabético')),
                ButtonSegment(
                    value: OrdenLista.empresa, label: Text('Por empresa')),
                ButtonSegment(
                    value: OrdenLista.cronologico, label: Text('Cronológico')),
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
          // Una sola barra, como el orden de arriba, y entera en pantalla. Deslizarla dejaba
          // filtros fuera del borde —y el primero cortado—, que es peor que leerla algo más
          // chica: se encoge lo justo para caber y no se parte en dos renglones.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SegmentedButton<FiltroLista>(
                segments: [
                  _segmento(FiltroLista.porServir, 'Por servir', porServir),
                  _segmento(FiltroLista.servidos, 'Servidos', servidos),
                  _segmento(
                      FiltroLista.noCancelados, 'No cancelados', noCancelados),
                  _segmento(FiltroLista.paraLlevar, 'Llevar', llevar),
                  _segmento(FiltroLista.anulados, 'Anulados', anulados),
                  _segmento(FiltroLista.todos, 'Todos', base.length - anulados),
                ],
                selected: {_filtro},
                onSelectionChanged: (f) => setState(() => _filtro = f.first),
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
              ),
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
                      if (fila is GrupoDeEmpresa) {
                        return _Encabezado(grupo: fila);
                      }
                      final t = fila as Ticket;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (i > 0 && filas[i - 1] is Ticket)
                            const Divider(height: 1),
                          // Se anula arrastrando la fila hacia la derecha, como se archiva
                          // un correo. Un botón de anular al lado del de marcar es un error
                          // de un centímetro con la fila esperando; el gesto hay que hacerlo
                          // a propósito, y encima pide confirmación.
                          if (t.estado == EstadoTicket.vigente ||
                              t.estado == EstadoTicket.noCancelado)
                            Dismissible(
                              key: ValueKey('anular-${t.id}'),
                              direction: DismissDirection.startToEnd,
                              // Hay que arrastrar más de un tercio del ancho: un roce al
                              // desplazar la lista no alcanza.
                              dismissThresholds: const {DismissDirection.startToEnd: 0.35},
                              background: const _FondoAnular(),
                              confirmDismiss: (_) => _confirmarAnular(t),
                              child: _Fila(
                                  ticket: t,
                                  onMarcar: () => _marcar(t),
                                  numeroDeOpcion:
                                      dia?.numeroDeOpcionPorNombre(t.opcion) ?? 0),
                            )
                          else
                            _Fila(
                                ticket: t,
                                onMarcar: () => _marcar(t),
                                numeroDeOpcion:
                                    dia?.numeroDeOpcionPorNombre(t.opcion) ?? 0),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Pregunta antes de anular y, si dicen que sí, lo manda.
  ///
  /// Devuelve false siempre: la fila no se saca de la lista al anularla, se queda tachada.
  /// Sacarla haría desaparecer de la pantalla a quien está parado al frente preguntando qué
  /// pasó, y el mesón necesita poder mostrarle la hora de su anulación.
  Future<bool> _confirmarAnular(Ticket t) async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Anular a esta persona?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t.persona, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text([t.codigoLegible, t.opcion, if (t.empresa != null) t.empresa!].join(' · '),
              style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 12),
          const Text('Queda sin almuerzo para hoy y se libera su cupo.'),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC0392B)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Anular'),
          ),
        ],
      ),
    );

    if (confirmado != true || !mounted) return false;

    final r = await widget.estado.anular(t);
    if (!mounted) return false;

    final mensaje = switch (r.resultado) {
      ResultadoAnular.ok => '${t.persona} quedó anulado',
      ResultadoAnular.yaAnulada => 'Ya estaba anulada',
      ResultadoAnular.yaServida => 'Ya pasó por la fila: eso no se anula',
      ResultadoAnular.diaCerrado => 'El día ya está cerrado',
      ResultadoAnular.noEncontrada => 'Esa reserva no es de hoy ni de este casino',
      ResultadoAnular.sinConexion => 'Sin señal: anular necesita conexión',
      ResultadoAnular.error => 'No se pudo anular',
    };

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r.mensaje ?? mensaje),
      backgroundColor: r.resultado == ResultadoAnular.ok ? null : const Color(0xFFC0392B),
    ));

    setState(() {});
    return false;
  }

  /// Un filtro de la barra, con su cuenta.
  ///
  /// El número va en su propia burbuja y no entre paréntesis: pegado al texto se leía como
  /// parte del nombre del filtro. Y el segmento entero en una sola línea, porque partir
  /// «No cancelados» en dos renglones desordena toda la barra.
  ButtonSegment<FiltroLista> _segmento(
          FiltroLista filtro, String texto, int cuantos) =>
      ButtonSegment(
        value: filtro,
        label: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(texto, softWrap: false, style: const TextStyle(fontSize: 13.5)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: const Color(0x14372B62),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('$cuantos',
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800, height: 1.25)),
          ),
        ]),
      );

  /// Qué decir cuando no hay nada que mostrar. «Nadie calza con la búsqueda» sobre una
  /// lista de servidos vacía hace pensar que se perdieron los datos.
  String _vacio() {
    if (_busqueda.isNotEmpty) return 'Nadie calza con la búsqueda';
    return switch (_filtro) {
      FiltroLista.porServir => 'No queda nadie por servir',
      FiltroLista.servidos => 'Todavía no se ha servido a nadie',
      FiltroLista.noCancelados => 'Nadie quedó como no cancelado',
      FiltroLista.paraLlevar => 'Nadie pidió para llevar',
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Marcar')),
        ],
      ),
    );
    if (confirmado != true) return;

    final resultado =
        (await widget.estado.marcar(t.token.isNotEmpty ? t.token : t.codigo))
            .resultado;
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(switch (resultado) {
        ResultadoMarca.ok => '${t.persona}: servido',
        ResultadoMarca.yaConsumido => '${t.persona} ya estaba servido',
        ResultadoMarca.anulado => 'Ese ticket está anulado',
        ResultadoMarca.fueraDeLaCopia =>
          'No está en la lista bajada; actualiza',
        ResultadoMarca.desactivado =>
          '${t.persona} está desactivado por su empresa',
        ResultadoMarca.valeCobrado => '${t.persona}: vale cobrado',
        ResultadoMarca.valeYaUsado => 'Ese vale ya se usó',
        ResultadoMarca.valeReservado =>
          '${t.persona} tiene almuerzo reservado con ese ticket',
        ResultadoMarca.sinTicket => '${t.persona} está anotado pero sin ticket',
        ResultadoMarca.vencido => 'Ese ticket está vencido',
        _ => 'No se pudo marcar',
      }),
    ));
    setState(() {});
  }
}

class _Fila extends StatelessWidget {
  const _Fila(
      {required this.ticket, required this.onMarcar, this.numeroDeOpcion = 0});

  final Ticket ticket;
  final VoidCallback onMarcar;

  /// El número de la opción en la minuta —1, 2, 3—, que es como se piden los platos en el
  /// mesón. Cero si no se pudo resolver contra las opciones del día.
  final int numeroDeOpcion;

  @override
  Widget build(BuildContext context) {
    final servido = ticket.estado == EstadoTicket.servido;
    final anulado = ticket.estado == EstadoTicket.anulado;
    final noCancelado = ticket.estado == EstadoTicket.noCancelado;
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
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFC2410C))),
          ),
        Expanded(
          child: Text(ticket.persona,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: anulado ? Colors.black45 : null,
                  decoration:
                      servido || anulado ? TextDecoration.lineThrough : null)),
        ),
        if (noCancelado)
          Container(
            margin: const EdgeInsets.only(left: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: const Color(0xFFB45309).withValues(alpha: .14),
                borderRadius: BorderRadius.circular(999)),
            child: const Text('NO CANCELADO',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFB45309))),
          ),
        if (ticket.acreditada)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
                color: const Color(0xFF372B62).withValues(alpha: .12),
                borderRadius: BorderRadius.circular(999)),
            child: const Text('con QR',
                style: TextStyle(fontSize: 11, color: Color(0xFF372B62))),
          ),
      ]),
      subtitle: Text([
            ticket.codigoLegible,
            ticket.opcion,
            if (ticket.empresa != null) ticket.empresa!,
            if (ticket.area != null && ticket.area!.isNotEmpty) ticket.area!,
            // La hora de quien ya pasó: es lo primero que se pregunta cuando alguien dice que no
            // lo atendieron.
            if (servido && ticket.consumidoUtc != null)
              'servido ${_hora(ticket.consumidoUtc!)}',
            if (anulado)
              ticket.anuladoUtc != null
                  ? 'ANULADO ${_hora(ticket.anuladoUtc!)}'
                  : 'ANULADO',
          ].join(' · ')
          // Lo que la persona escribió al anotarse: alergias, sin ají, doble arroz. De nada
          // sirve guardarlo si quien sirve el plato no lo ve.
          +
          (ticket.comentario == null || ticket.comentario!.isEmpty
              ? ''
              : '\n«${ticket.comentario}»')),
      isThreeLine: ticket.comentario != null && ticket.comentario!.isNotEmpty,
      // La opción va pegada al botón y con color propio: quien sirve mira esa esquina de la
      // pantalla, no el renglón de datos. Con dos o tres platos, el color se reconoce antes
      // de alcanzar a leer el número.
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (numeroDeOpcion > 0) _EtiquetaOpcion(numero: numeroDeOpcion),
        const SizedBox(width: 10),
        if (anulado)
          // Un anulado no se sirve: no hay botón que apretar, solo el rastro de que existió.
          const Icon(Icons.cancel, color: Color(0xFFC0392B))
        else if (servido)
          const Icon(Icons.check_circle, color: Color(0xFF146C4E))
        else
          FilledButton(onPressed: onMarcar, child: const Text('Marcar')),
      ]),
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
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
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

/// El número de la opción, con su color.
///
/// El color no decora: en una tablet apoyada en el mesón, con la fila esperando, se reconoce
/// «la 1» por el color antes de alcanzar a leer. Por eso es siempre el mismo para el mismo
/// número, y viene de la posición en la minuta, que la fija el administrador.
class _EtiquetaOpcion extends StatelessWidget {
  const _EtiquetaOpcion({required this.numero});

  final int numero;

  /// Colores bien distintos entre sí, no una gama: la diferencia tiene que notarse de reojo.
  static const _colores = [
    Color(0xFF372B62), // morado Makki
    Color(0xFFC2410C), // terracota
    Color(0xFF146C4E), // verde
    Color(0xFF1F6F8B), // azul
    Color(0xFF8C2318), // burdeo
  ];

  @override
  Widget build(BuildContext context) {
    final color = _colores[(numero - 1) % _colores.length];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        border: Border.all(color: color.withValues(alpha: .55)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text('Opción $numero',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w800, color: color)),
    );
  }
}


/// Lo que se ve debajo de la fila mientras se la arrastra: rojo y con la palabra, para que
/// quede claro qué va a pasar antes de soltar.
class _FondoAnular extends StatelessWidget {
  const _FondoAnular();

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFC0392B),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.block, color: Colors.white),
          SizedBox(width: 10),
          Text('Anular',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
        ]),
      );
}
