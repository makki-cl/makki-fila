import 'package:flutter/material.dart';

import '../api/models.dart';
import '../app_state.dart';

/// Anotar a alguien en el mesón, con la fila andando.
///
/// Existe porque el que llega sin haberse inscrito ya está parado ahí: decirle «no estás en
/// la lista» no lo devuelve a su oficina. Si la opción que quiere está llena, se anota igual
/// sumando una ración —sobrecupo—, pero hay que apretarlo a propósito y queda escrito.
class AnotarScreen extends StatefulWidget {
  const AnotarScreen({super.key, required this.estado});

  final AppState estado;

  @override
  State<AnotarScreen> createState() => _AnotarScreenState();
}

class _AnotarScreenState extends State<AnotarScreen> {
  final _nombre = TextEditingController();
  final _correo = TextEditingController();
  final _otraEmpresa = TextEditingController();

  String? _opcionId;
  String? _empresaId;
  bool _paraLlevar = false;
  bool _enviando = false;
  String? _error;

  /// Valor del selector para la visita que no pertenece a ninguna empresa con convenio.
  static const _otra = 'otra';

  @override
  void dispose() {
    _nombre.dispose();
    _correo.dispose();
    _otraEmpresa.dispose();
    super.dispose();
  }

  OpcionMenu? get _opcion =>
      widget.estado.dia?.opciones.where((o) => o.id == _opcionId).firstOrNull;

  bool get _sinCupo => _opcion != null && _opcion!.tomados >= _opcion!.cupo;

  Future<void> _anotar() async {
    final dia = widget.estado.dia;
    if (dia == null || _opcionId == null || _nombre.text.trim().isEmpty) {
      setState(() => _error = 'Falta la opción o el nombre');
      return;
    }
    if (_empresaId == null) {
      setState(() => _error = 'Elige la empresa');
      return;
    }
    if (_empresaId == _otra && _otraEmpresa.text.trim().isEmpty) {
      setState(() => _error = 'Escribe de qué empresa viene');
      return;
    }

    // El sobrecupo se confirma aparte: suma una ración que alguien tiene que cocinar.
    if (_sinCupo) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('No queda cupo'),
          content: Text('«${_opcion!.nombre}» está lleno. Anotar a ${_nombre.text.trim()} '
              'suma una ración al día y queda registrado.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true), child: const Text('Anotar igual')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() {
      _enviando = true;
      _error = null;
    });

    final r = await widget.estado.anotar(
      menuItemId: _opcionId!,
      nombre: _nombre.text.trim(),
      empresaId: _empresaId == _otra ? null : _empresaId,
      otraEmpresa: _empresaId == _otra ? _otraEmpresa.text.trim() : null,
      correo: _correo.text.trim(),
      paraLlevar: _paraLlevar,
      sobrecupo: _sinCupo,
    );

    if (!mounted) return;
    setState(() => _enviando = false);

    if (r.resultado == ResultadoAnotar.ok) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.sobrecupo
            ? '${_nombre.text.trim()} anotado en sobrecupo · ${r.codigo ?? ''}'
            : '${_nombre.text.trim()} anotado · ${r.codigo ?? ''}'),
      ));
      return;
    }

    setState(() => _error = switch (r.resultado) {
          ResultadoAnotar.sinCupo => 'Esa opción no tiene cupo',
          ResultadoAnotar.cerrada => 'El día está cerrado: ya no se anota a nadie',
          ResultadoAnotar.sinConexion =>
            'Sin conexión: anotar necesita servidor, porque el cupo vive allá',
          _ => r.mensaje ?? 'No se pudo anotar',
        });
  }

  @override
  Widget build(BuildContext context) {
    final dia = widget.estado.dia;

    return Scaffold(
      appBar: AppBar(title: const Text('Anotar comensal')),
      body: dia == null
          ? const Center(child: Text('Todavía no se ha bajado el día'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _opcionId,
                  decoration: const InputDecoration(labelText: 'Opción', border: OutlineInputBorder()),
                  // Salen todas, con cupo o sin él: el que llega ya está en el mesón.
                  items: [
                    for (final (n, o) in dia.opciones.indexed)
                      DropdownMenuItem(
                        value: o.id,
                        child: Text(o.tomados < o.cupo
                            ? 'Opción ${n + 1} · ${o.nombre}  (${o.cupo - o.tomados} libres)'
                            : 'Opción ${n + 1} · ${o.nombre}  · SIN CUPO'),
                      ),
                  ],
                  onChanged: (v) => setState(() => _opcionId = v),
                ),
                if (_sinCupo)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDF6E7),
                        border: Border.all(color: const Color(0xFFE0A030)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Esa opción está llena. Si lo anotas igual, se suma una ración al día '
                        'y queda registrado quién lo hizo.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _empresaId,
                  decoration: const InputDecoration(labelText: 'Empresa', border: OutlineInputBorder()),
                  items: [
                    for (final e in dia.empresas)
                      DropdownMenuItem(value: e.id, child: Text(e.nombre)),
                    const DropdownMenuItem(value: _otra, child: Text('Otra (escribirla)')),
                  ],
                  onChanged: (v) => setState(() => _empresaId = v),
                ),
                if (_empresaId == _otra) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _otraEmpresa,
                    decoration: const InputDecoration(
                        labelText: '¿De qué empresa viene?', border: OutlineInputBorder()),
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: _nombre,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _correo,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                      labelText: 'Correo (opcional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 6),
                CheckboxListTile(
                  value: _paraLlevar,
                  onChanged: (v) => setState(() => _paraLlevar = v ?? false),
                  title: const Text('Para llevar'),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(_error!, style: const TextStyle(color: Color(0xFFC0392B))),
                  ),
                FilledButton.icon(
                  onPressed: _enviando ? null : _anotar,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    backgroundColor: _sinCupo ? const Color(0xFFC2410C) : null,
                  ),
                  icon: Icon(_sinCupo ? Icons.add_alert : Icons.person_add),
                  label: Text(_sinCupo ? 'Anotar en sobrecupo' : 'Anotar',
                      style: const TextStyle(fontSize: 17)),
                ),
              ],
            ),
    );
  }
}
