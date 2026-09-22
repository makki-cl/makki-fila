import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../api/models.dart';
import '../app_state.dart';
import '../formato.dart';

/// El lector. Está pensado para una fila: la respuesta ocupa media pantalla, se lee de lejos
/// y en un segundo se vuelve a la cámara para el siguiente.
///
/// En la caja el ritmo es otro —hay que leer cuánto se cobró y si falta efectivo— así que la
/// respuesta se queda en pantalla hasta que la persona del mesón la toca.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.estado, this.monto});

  final AppState estado;

  /// Total de la compra, cuando se está cobrando en la caja. Vacío = se gasta el vale completo.
  final num? monto;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late MobileScannerController _camara = _nuevaCamara();

  RespuestaMarca? _respuesta;
  bool _procesando = false;

  bool get _enCaja => widget.estado.modo == ModoMeson.caja;

  MobileScannerController _nuevaCamara() => MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        formats: const [BarcodeFormat.qrCode],
        cameraResolution: widget.estado.resolucion.tamano,
        facing: widget.estado.camaraFrontal ? CameraFacing.front : CameraFacing.back,
      );

  /// Rehace la cámara con lo que se acaba de elegir. No basta con cambiar el ajuste: la
  /// resolución se fija al abrir el dispositivo, así que hay que cerrarlo y abrirlo de nuevo.
  Future<void> _rehacerCamara() async {
    final vieja = _camara;
    setState(() => _camara = _nuevaCamara());
    await vieja.dispose();
  }

  @override
  void dispose() {
    _camara.dispose();
    super.dispose();
  }

  Future<void> _alLeer(BarcodeCapture captura) async {
    if (_procesando) return;
    final valor = captura.barcodes.firstOrNull?.rawValue;
    if (valor == null || valor.isEmpty) return;
    await _marcar(valor, esperaAntesDeSeguir: const Duration(milliseconds: 1600));
  }

  Future<void> _marcar(String lectura, {required Duration esperaAntesDeSeguir}) async {
    setState(() => _procesando = true);
    final respuesta = await widget.estado.marcar(lectura, monto: widget.monto);

    // El mesón mira al comensal, no a la pantalla: la respuesta también se siente.
    final bien = respuesta.resultado == ResultadoMarca.ok ||
        respuesta.resultado == ResultadoMarca.valeCobrado;
    if (bien) {
      await HapticFeedback.mediumImpact();
    } else {
      await HapticFeedback.heavyImpact();
      await SystemSound.play(SystemSoundType.alert);
    }

    if (!mounted) return;
    setState(() => _respuesta = respuesta);

    // En la caja la pantalla la cierra quien atiende: recién cobró plata y tiene que leer si
    // falta efectivo. En la fila vuelve sola, porque nadie tiene una mano libre para tocar.
    if (_enCaja) return;

    await Future<void>.delayed(esperaAntesDeSeguir);
    if (!mounted) return;
    setState(() {
      _respuesta = null;
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
    await _marcar(codigo, esperaAntesDeSeguir: const Duration(milliseconds: 2200));
  }

  /// Ajustes de la cámara de ESTE equipo.
  ///
  /// Hay tablets cuyo driver entrega el cuadro mal y la pantalla muestra bandas de colores en
  /// vez de la imagen. Cuál resolución funciona depende del aparato, así que se prueba acá
  /// mismo, con la cámara a la vista, en vez de esperar una versión nueva de la aplicación.
  Future<void> _ajustarCamara() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('La cámara se ve mal'),
        content: StatefulBuilder(
          builder: (ctx, redibujar) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Si en vez de la imagen salen bandas de colores, prueba otra resolución: '
                'cierra este cuadro y mira. Lo que elijas se queda guardado en este equipo.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              RadioGroup<ResolucionCamara>(
                groupValue: widget.estado.resolucion,
                onChanged: (v) async {
                  if (v == null) return;
                  await widget.estado.cambiarResolucion(v);
                  redibujar(() {});
                  await _rehacerCamara();
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final r in ResolucionCamara.values)
                      RadioListTile<ResolucionCamara>(
                        value: r,
                        dense: true,
                        title: Text(r.etiqueta),
                      ),
                  ],
                ),
              ),
              const Divider(),
              SwitchListTile(
                value: widget.estado.camaraFrontal,
                dense: true,
                title: const Text('Usar la cámara de adelante'),
                subtitle: const Text('Por si la de atrás está fallando', style: TextStyle(fontSize: 12)),
                onChanged: (v) async {
                  await widget.estado.cambiarCamara(v);
                  redibujar(() {});
                  await _rehacerCamara();
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Listo')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_enCaja
            ? (widget.monto == null ? 'Cobrar el vale completo' : 'Cobrar ${pesos(widget.monto!)}')
            : 'Escanear QR'),
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
          IconButton(
            onPressed: _ajustarCamara,
            icon: const Icon(Icons.tune),
            tooltip: 'La cámara se ve mal',
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            key: ValueKey('${widget.estado.resolucion.name}-${widget.estado.camaraFrontal}'),
            controller: _camara,
            onDetect: _alLeer,
          ),
          if (_respuesta != null)
            GestureDetector(
              // Solo cierra al tocar en la caja; en la fila la pantalla se va sola y un toque
              // accidental no debe adelantar al siguiente comensal.
              onTap: _enCaja ? () => Navigator.of(context).pop(_respuesta) : null,
              child: _Veredicto(
                respuesta: _respuesta!,
                enCaja: _enCaja,
                montoPedido: widget.monto,
                horaCopia: widget.estado.horaDeLaCopia,
              ),
            ),
          if (_respuesta == null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  _enCaja
                      ? 'Apunta al QR del vale · si la imagen se ve rara, toca el control de arriba'
                      : 'Apunta al QR del comensal · si la imagen se ve rara, toca el control de arriba',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
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
  const _Veredicto({
    required this.respuesta,
    required this.enCaja,
    this.montoPedido,
    this.horaCopia,
  });

  final RespuestaMarca respuesta;
  final bool enCaja;
  final num? montoPedido;
  final String? horaCopia;

  static const _verde = Color(0xFF146C4E);
  static const _naranjo = Color(0xFFC2410C);
  static const _rojo = Color(0xFFC0392B);

  @override
  Widget build(BuildContext context) {
    final ticket = respuesta.ticket;
    final (color, icono, titulo) = switch (respuesta.resultado) {
      ResultadoMarca.ok => (_verde, Icons.check_circle, 'Puede pasar'),
      ResultadoMarca.yaConsumido => (_naranjo, Icons.info, 'Ya fue servido'),
      ResultadoMarca.anulado => (_rojo, Icons.cancel, 'Ticket anulado'),
      ResultadoMarca.otroDia => (_rojo, Icons.event_busy, 'No es de hoy o de este casino'),
      ResultadoMarca.fueraDeLaCopia => (_rojo, Icons.help_outline, 'No está en la lista de hoy'),
      ResultadoMarca.sinConexion => (
          _rojo,
          Icons.wifi_off,
          enCaja ? 'Sin conexión: no se puede cobrar' : 'Sin conexión y sin copia del día'
        ),
      ResultadoMarca.desactivado => (_rojo, Icons.person_off, 'Su empresa lo desactivó'),
      ResultadoMarca.valeCobrado => (
          _verde,
          Icons.check_circle,
          respuesta.monto == null ? 'Vale cobrado' : 'Cobrado ${pesos(respuesta.monto!)}'
        ),
      ResultadoMarca.valeYaUsado => (_naranjo, Icons.info, 'Ese vale ya se usó'),
      ResultadoMarca.valeReservado => (
          _naranjo,
          Icons.restaurant,
          'Tiene almuerzo reservado con este ticket'
        ),
      ResultadoMarca.sinTicket => (
          _rojo,
          Icons.confirmation_number_outlined,
          'Anotado, pero sin ticket'
        ),
      ResultadoMarca.soloParaAlmuerzo => (_rojo, Icons.no_food, 'Sirve solo para el almuerzo'),
      ResultadoMarca.vencido => (_rojo, Icons.event_busy, 'Ticket vencido'),
      ResultadoMarca.noExiste => (_rojo, Icons.help, 'Ticket desconocido'),
    };

    return Container(
      color: color,
      alignment: Alignment.center,
      child: SingleChildScrollView(
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
              for (final linea in _explicacion())
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(linea,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 16)),
                ),
              if (_efectivoQueFalta() case final falta?)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('Cobra ${pesos(falta)} en efectivo',
                        style: TextStyle(
                            color: color, fontSize: 24, fontWeight: FontWeight.w800)),
                  ),
                ),
              if (respuesta.nombre case final nombre? when nombre.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text(nombre,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 22)),
              ],
              if (ticket != null) ...[
                Text(
                  [ticket.empresa, ticket.opcion]
                      .where((t) => t != null && t.isNotEmpty)
                      .join(' · '),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                Text(ticket.codigoLegible,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 16, fontFamily: 'monospace')),
                if (ticket.comentario != null && ticket.comentario!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text('Observación: ${ticket.comentario}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 15)),
                  ),
                if (respuesta.resultado == ResultadoMarca.yaConsumido &&
                    ticket.consumidoUtc != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Se sirvió a las ${_hora(ticket.consumidoUtc!)}',
                        style: const TextStyle(color: Colors.white70)),
                  ),
              ],
              if (enCaja)
                const Padding(
                  padding: EdgeInsets.only(top: 22),
                  child: Text('Toca para seguir',
                      style: TextStyle(color: Colors.white70, fontSize: 15)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Lo que hay que hacer, en una frase. Nada de explicar el sistema: en el mesón se lee de
  /// pie y con gente esperando.
  List<String> _explicacion() => switch (respuesta.resultado) {
        ResultadoMarca.desactivado => [
            'Que hable con quien administra el casino en su empresa.'
          ],
        ResultadoMarca.sinTicket => [
            'Su empresa todavía no le entrega el ticket. No se le sirve.'
          ],
        ResultadoMarca.valeReservado => [
            enCaja
                ? 'Su almuerzo está reservado con este ticket: acá no se cobra.'
                : 'Sírvele en la fila; acá no se cobra.'
          ],
        ResultadoMarca.soloParaAlmuerzo => [
            'Su empresa lo convino solo para el almuerzo. Si lleva otra cosa, se paga aparte.'
          ],
        ResultadoMarca.vencido => ['Ya no sirve. Su empresa tiene que entregarle otro.'],
        ResultadoMarca.valeYaUsado => [
            if (respuesta.monto != null) 'Se gastó ${pesos(respuesta.monto!)}.',
          ],
        ResultadoMarca.sinConexion => [
            if (enCaja) 'Cóbralo en efectivo: sin servidor no hay cómo saber si el vale sirve.',
          ],
        ResultadoMarca.valeCobrado => [
            if (_saldoQueSePierde() case final saldo?)
              'El vale era de ${pesos(respuesta.valor!)} y se gasta completo: '
                  'los ${pesos(saldo)} de diferencia no se devuelven.'
            else if (!enCaja)
              'Es un ticket acumulado, no una inscripción del día: no trae plato elegido.',
          ],
        ResultadoMarca.fueraDeLaCopia => [
            'La copia es de las ${horaCopia ?? '—'}. Si la persona se anotó después, '
                'actualiza; si no, el código no corresponde a este día.'
          ],
        _ => const [],
      };

  /// Lo que la compra se pasó del valor del ticket: eso lo paga la persona.
  num? _efectivoQueFalta() {
    if (respuesta.resultado != ResultadoMarca.valeCobrado) return null;
    final pedido = montoPedido;
    final valor = respuesta.valor;
    if (pedido == null || valor == null || pedido <= valor) return null;
    return pedido - valor;
  }

  /// Lo que quedaba en el ticket y se pierde, cuando la compra fue menor que su valor.
  num? _saldoQueSePierde() {
    if (!enCaja) return null;
    final cobrado = respuesta.monto;
    final valor = respuesta.valor;
    if (cobrado == null || valor == null || valor <= cobrado) return null;
    return valor - cobrado;
  }

  /// Hora local del equipo: el servidor guarda en UTC y el mesón piensa en hora de Chile.
  static String _hora(DateTime utc) {
    final l = utc.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}
