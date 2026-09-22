import 'package:flutter/material.dart';

import '../actualizacion.dart';
import '../api/models.dart';
import '../app_state.dart';
import 'anotar_screen.dart';
import 'caja_screen.dart';
import 'vivo_screen.dart';
import 'list_screen.dart';
import 'scan_screen.dart';

/// Pantalla principal del mesón: qué se está sirviendo hoy, cómo va la fila y los dos botones
/// que se usan de verdad — escanear y buscar a alguien en la lista.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.estado});

  final AppState estado;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Actualizacion? _nueva;
  double? _bajando;

  @override
  void initState() {
    super.initState();
    // Se pregunta una vez al abrir. Si no hay señal o no hay nada nuevo, no se dice nada:
    // el mesón no tiene por qué enterarse de que se buscó.
    Actualizacion.buscar().then((a) {
      if (mounted && a != null) setState(() => _nueva = a);
    });
  }

  Future<void> _actualizar() async {
    setState(() => _bajando = 0);
    final error = await _nueva!.instalar(
      avance: (p) { if (mounted) setState(() => _bajando = p); },
    );
    if (!mounted) return;
    setState(() => _bajando = null);
    if (error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo actualizar: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = widget.estado;
    final dia = estado.dia;

    return Scaffold(
      appBar: AppBar(
        title: Text(estado.sesion?.unitName ?? 'Makki · Fila'),
        actions: [
          if (estado.pendientes > 0)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton.icon(
                onPressed: () async {
                  final r = await estado.sincronizar();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(mensajeDeSincronia(r))),
                    );
                  }
                },
                icon: const Icon(Icons.cloud_upload, color: Colors.white),
                label: Text('${estado.pendientes}', style: const TextStyle(color: Colors.white)),
              ),
            ),
          IconButton(
            onPressed: estado.cargando ? null : estado.refrescar,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'operador') _pedirOperador(context);
              if (v == 'salir') estado.desenrolar();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'operador', child: Text('Quién está en el mesón')),
              PopupMenuItem(value: 'salir', child: Text('Desvincular este equipo')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: estado.refrescar,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_nueva != null) _AvisoActualizacion(
              version: _nueva!.version,
              avance: _bajando,
              onActualizar: _actualizar,
            ),
            if (estado.pendientes > 0)
              _Aviso(
                color: const Color(0xFFFDF6E7),
                borde: const Color(0xFFE0A030),
                icono: Icons.cloud_off,
                texto: '${estado.pendientes} marca(s) sin enviar. Se guardaron acá y se '
                    'mandarán solas al recuperar señal.',
              ),
            _SelectorDeModo(estado: estado),
            const SizedBox(height: 16),
            if (estado.modo == ModoMeson.caja)
              const _Aviso(
                color: Color(0xFFF1F5F9),
                borde: Color(0xFF291F47),
                icono: Icons.point_of_sale,
                texto: 'Este equipo está cobrando vales en la caja. Los almuerzos de la minuta '
                    'se marcan desde el modo fila.',
              )
            else if (dia == null)
              const _Aviso(
                color: Color(0xFFFDECEA),
                borde: Color(0xFFC0392B),
                icono: Icons.wifi_off,
                texto: 'Todavía no se ha bajado ningún día. Conéctate y toca actualizar.',
              )
            else ...[
              Text(dia.fecha,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              Text('${dia.unidad} · minuta ${dia.estado}',
                  style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 16),
              Row(
                children: [
                  _Contador(titulo: 'Emitidos', valor: dia.emitidos),
                  _Contador(titulo: 'Servidos', valor: dia.servidos),
                  _Contador(titulo: 'Por servir', valor: dia.porServir, destacado: true),
                ],
              ),
              const SizedBox(height: 16),
              for (final o in dia.opciones) _FilaOpcion(opcion: o),
              if (dia.nota != null && dia.nota!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(dia.nota!, style: const TextStyle(color: Colors.black54)),
              ],
            ],
            const SizedBox(height: 24),
            if (estado.modo == ModoMeson.caja)
              // La caja no depende de la copia del día: un vale no cuelga de ninguna minuta,
              // así que se puede cobrar aunque hoy no haya menú publicado.
              FilledButton.icon(
                onPressed: () => _abrir(context, CajaScreen(estado: estado)),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 22)),
                icon: const Icon(Icons.point_of_sale, size: 28),
                label: const Text('Cobrar en la caja', style: TextStyle(fontSize: 18)),
              )
            else ...[
              FilledButton.icon(
                onPressed: dia == null ? null : () => _abrir(context, ScanScreen(estado: estado)),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 22)),
                icon: const Icon(Icons.qr_code_scanner, size: 28),
                label: const Text('Escanear QR', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: dia == null ? null : () => _abrir(context, VivoScreen(estado: estado)),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                icon: const Icon(Icons.bolt),
                label: const Text('Cómo va el día', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: dia == null ? null : () => _abrir(context, AnotarScreen(estado: estado)),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                icon: const Icon(Icons.person_add),
                label: const Text('Anotar comensal', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: dia == null ? null : () => _abrir(context, ListScreen(estado: estado)),
                style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                icon: const Icon(Icons.list_alt),
                label: const Text('Lista de anotados', style: TextStyle(fontSize: 16)),
              ),
            ],
            if (estado.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(estado.error!,
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }

  void _abrir(BuildContext context, Widget pantalla) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => pantalla));

  /// Quién opera queda registrado en cada marca: el permiso es del equipo, pero la
  /// responsabilidad de quien marcó tiene que quedar escrita.
  Future<void> _pedirOperador(BuildContext context) async {
    final control = TextEditingController(text: widget.estado.operador);
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quién está en el mesón'),
        content: TextField(
          controller: control,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Nombre'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, control.text), child: const Text('Guardar')),
        ],
      ),
    );
    if (nombre != null) await widget.estado.guardarOperador(nombre);
  }
}

/// Fila o caja. Está arriba de todo y siempre a la vista porque de esto depende qué queda
/// registrado: un ticket marcado en el modo equivocado ensucia el informe del mes.
class _SelectorDeModo extends StatelessWidget {
  const _SelectorDeModo({required this.estado});

  final AppState estado;

  @override
  Widget build(BuildContext context) => SegmentedButton<ModoMeson>(
        segments: const [
          ButtonSegment(
            value: ModoMeson.fila,
            icon: Icon(Icons.restaurant),
            label: Text('Fila'),
          ),
          ButtonSegment(
            value: ModoMeson.caja,
            icon: Icon(Icons.point_of_sale),
            label: Text('Caja'),
          ),
        ],
        selected: {estado.modo},
        onSelectionChanged: (s) => estado.cambiarModo(s.first),
        showSelectedIcon: false,
      );
}

class _Contador extends StatelessWidget {
  const _Contador({required this.titulo, required this.valor, this.destacado = false});

  final String titulo;
  final int valor;
  final bool destacado;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFE0E4DE)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo.toUpperCase(),
                  style: const TextStyle(fontSize: 10, letterSpacing: 1, color: Colors.black54)),
              Text('$valor',
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: destacado ? const Color(0xFF372B62) : Colors.black87)),
            ],
          ),
        ),
      );
}

class _FilaOpcion extends StatelessWidget {
  const _FilaOpcion({required this.opcion});

  final OpcionMenu opcion;

  @override
  Widget build(BuildContext context) {
    final proporcion = opcion.cupo == 0 ? 0.0 : opcion.tomados / opcion.cupo;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text(opcion.nombre, style: const TextStyle(fontWeight: FontWeight.w600))),
              Text('${opcion.tomados} / ${opcion.cupo}',
                  style: const TextStyle(fontFamily: 'monospace')),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: proporcion.clamp(0.0, 1.0),
              minHeight: 7,
              backgroundColor: const Color(0xFFEDF0EA),
              color: proporcion >= 1 ? const Color(0xFFC2410C) : const Color(0xFF372B62),
            ),
          ),
        ],
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.color, required this.borde, required this.icono, required this.texto});

  final Color color;
  final Color borde;
  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: borde.withValues(alpha: .4)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(icono, color: borde, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 13))),
        ]),
      );
}

/// El aviso de versión nueva. Arriba de todo y con el botón a mano: si hay que ir a buscarla
/// a una pantalla de ajustes, los equipos se quedan atrás para siempre.
class _AvisoActualizacion extends StatelessWidget {
  const _AvisoActualizacion(
      {required this.version, required this.avance, required this.onActualizar});

  final String version;
  final double? avance;
  final VoidCallback onActualizar;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFEFEDF7),
          border: Border.all(color: const Color(0xFF372B62)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          const Icon(Icons.system_update, color: Color(0xFF372B62)),
          const SizedBox(width: 10),
          Expanded(
            child: avance == null
                ? Text('Hay una versión nueva: $version',
                    style: const TextStyle(fontWeight: FontWeight.w600))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Bajando ${(avance! * 100).round()}%'),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                            value: avance, minHeight: 6, color: const Color(0xFF372B62)),
                      ),
                    ],
                  ),
          ),
          if (avance == null)
            FilledButton(onPressed: onActualizar, child: const Text('Actualizar')),
        ]),
      );
}
