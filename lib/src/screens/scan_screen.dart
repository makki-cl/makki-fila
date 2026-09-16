import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../api/models.dart';
import '../app_state.dart';

/// El lector. Está pensado para una fila: la respuesta ocupa media pantalla, se lee de lejos
/// y en un segundo se vuelve a la cámara para el siguiente.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.estado});

  final AppState estado;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final MobileScannerController _camara = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  ResultadoMarca? _resultado;
  Ticket? _ticket;
  bool _procesando = false;

  @override
  void dispose() {
    _camara.dispose();
    super.dispose();
  }

  Future<void> _alLeer(BarcodeCapture captura) async {
    if (_procesando) return;
    final valor = captura.barcodes.firstOrNull?.rawValue;
    if (valor == null || valor.isEmpty) return;

    setState(() => _procesando = true);
    final (resultado, ticket) = await widget.estado.marcar(valor);

    // El mesón mira al comensal, no a la pantalla: la respuesta también se siente.
    if (resultado == ResultadoMarca.ok) {
      await HapticFeedback.mediumImpact();
    } else {
      await HapticFeedback.heavyImpact();
      await SystemSound.play(SystemSoundType.alert);
    }

    if (!mounted) return;
    setState(() {
      _resultado = resultado;
      _ticket = ticket;
    });

    // Vuelve a leer solo: nadie tiene una mano libre para tocar «siguiente».
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    setState(() {
      _resultado = null;
      _ticket = null;
      _procesando = false;
    });
  }

  /// Respaldo para cuando el teléfono del comensal no prende: se teclea el código de seis
  /// caracteres. Es el único camino para la gente de empresas acreditadas, que no aparece en
  /// la lista.
  Future<void> _pedirCodigo() async {
    final control = TextEditingController();
    final codigo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Código del ticket'),
        content: TextField(
          controller: control,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 26, letterSpacing: 4, fontFamily: 'monospace'),
          decoration: const InputDecoration(hintText: 'K7M-4QP'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, control.text), child: const Text('Buscar')),
        ],
      ),
    );

    if (codigo == null || codigo.trim().isEmpty) return;
    setState(() => _procesando = true);
    final (resultado, ticket) = await widget.estado.marcar(codigo);
    if (!mounted) return;
    setState(() {
      _resultado = resultado;
      _ticket = ticket;
    });
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    if (!mounted) return;
    setState(() {
      _resultado = null;
      _ticket = null;
      _procesando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Escanear QR'),
        actions: [
          IconButton(
            onPressed: _pedirCodigo,
            icon: const Icon(Icons.keyboard),
            tooltip: 'Ingresar código a mano',
          ),
          IconButton(
            onPressed: () => _camara.toggleTorch(),
            icon: const Icon(Icons.flashlight_on),
            tooltip: 'Linterna',
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(controller: _camara, onDetect: _alLeer),
          if (_resultado != null)
            _Veredicto(resultado: _resultado!, ticket: _ticket,
                       horaCopia: widget.estado.horaDeLaCopia),
          if (_resultado == null)
            const Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'Apunta al QR del comensal · el teclado de arriba es para dictar el código',
                  style: TextStyle(
                      color: Colors.white, fontSize: 16, backgroundColor: Colors.black54),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// La respuesta grande: color, título y a quién pertenece el ticket.
class _Veredicto extends StatelessWidget {
  const _Veredicto({required this.resultado, this.ticket, this.horaCopia});

  final ResultadoMarca resultado;
  final Ticket? ticket;
  final String? horaCopia;

  @override
  Widget build(BuildContext context) {
    final (color, icono, titulo) = switch (resultado) {
      ResultadoMarca.ok => (const Color(0xFF146C4E), Icons.check_circle, 'Puede pasar'),
      ResultadoMarca.yaConsumido => (const Color(0xFFC2410C), Icons.info, 'Ya fue servido'),
      ResultadoMarca.anulado => (const Color(0xFFC0392B), Icons.cancel, 'Ticket anulado'),
      ResultadoMarca.otroDia => (const Color(0xFFC0392B), Icons.event_busy, 'No es de hoy o de este casino'),
      ResultadoMarca.fueraDeLaCopia => (const Color(0xFFC0392B), Icons.help_outline,
          'No está en la lista de hoy'),
      ResultadoMarca.sinConexion => (const Color(0xFFC0392B), Icons.wifi_off,
          'Sin conexión y sin copia del día'),
      ResultadoMarca.noExiste => (const Color(0xFFC0392B), Icons.help, 'Ticket desconocido'),
    };

    return Container(
      color: color,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, color: Colors.white, size: 84),
            const SizedBox(height: 12),
            Text(titulo,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
            if (resultado == ResultadoMarca.fueraDeLaCopia)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Text(
                  'La copia es de las ${horaCopia ?? '—'}. Si la persona se anotó después, '
                  'actualiza; si no, el código no corresponde a este día.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ),
            if (ticket != null) ...[
              const SizedBox(height: 18),
              Text(ticket!.persona,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 22)),
              Text(
                [ticket!.empresa, ticket!.opcion].where((t) => t != null && t.isNotEmpty).join(' · '),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 16),
              ),
              Text(ticket!.codigoLegible,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 16, fontFamily: 'monospace')),
              if (ticket!.comentario != null && ticket!.comentario!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text('Observación: ${ticket!.comentario}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 15)),
                ),
              if (resultado == ResultadoMarca.yaConsumido && ticket!.consumidoUtc != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Se sirvió a las ${_hora(ticket!.consumidoUtc!)}',
                      style: const TextStyle(color: Colors.white70)),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Hora local del equipo: el servidor guarda en UTC y el mesón piensa en hora de Chile.
  static String _hora(DateTime utc) {
    final l = utc.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}
