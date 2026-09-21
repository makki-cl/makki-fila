import 'package:flutter/material.dart';

import '../api/models.dart';
import '../app_state.dart';
import '../formato.dart';
import 'scan_screen.dart';

/// La caja. Se escribe el total de la compra y recién después se abre la cámara.
///
/// Es al revés que la fila a propósito: acá se está cobrando plata, y un QR que entra solo
/// al campo de visión mientras alguien teclea cobraría un monto que nadie terminó de escribir.
class CajaScreen extends StatefulWidget {
  const CajaScreen({super.key, required this.estado});

  final AppState estado;

  @override
  State<CajaScreen> createState() => _CajaScreenState();
}

class _CajaScreenState extends State<CajaScreen> {
  /// Lo tecleado, en pesos. Cero = todavía no escriben nada.
  int _monto = 0;

  /// El último cobro, para que quede a la vista mientras se arma la compra siguiente.
  RespuestaMarca? _ultimo;

  void _digito(String d) {
    final texto = '$_monto$d';
    // Un millón de pesos en la caja de un casino no existe: el tope evita que un dedo pegado
    // al 0 deje un monto absurdo escrito.
    final valor = int.tryParse(texto) ?? _monto;
    if (valor > 999999) return;
    setState(() => _monto = valor);
  }

  void _borrar() => setState(() => _monto = _monto ~/ 10);

  Future<void> _cobrar() async {
    final respuesta = await Navigator.of(context).push<RespuestaMarca>(
      MaterialPageRoute(
        builder: (_) => ScanScreen(estado: widget.estado, monto: _monto == 0 ? null : _monto),
      ),
    );

    if (!mounted || respuesta == null) return;
    setState(() {
      _ultimo = respuesta;
      // El monto se limpia solo cuando el cobro salió: si el vale estaba vencido o era de
      // almuerzo, la compra sigue ahí esperando otra forma de pago.
      if (respuesta.resultado == ResultadoMarca.valeCobrado) _monto = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Caja')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TOTAL DE LA COMPRA',
                    style: TextStyle(fontSize: 11, letterSpacing: 1.2, color: Colors.black54)),
                const SizedBox(height: 4),
                Text(
                  _monto == 0 ? 'El vale completo' : pesos(_monto),
                  style: TextStyle(
                    fontSize: _monto == 0 ? 30 : 46,
                    fontWeight: FontWeight.w800,
                    color: _monto == 0 ? Colors.black45 : const Color(0xFF123528),
                  ),
                ),
                if (_ultimo != null) ...[
                  const Divider(height: 28),
                  _UltimoCobro(respuesta: _ultimo!),
                ],
              ],
            ),
          ),
          Expanded(child: _Teclado(onDigito: _digito, onBorrar: _borrar)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: FilledButton.icon(
              onPressed: _cobrar,
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 22)),
              icon: const Icon(Icons.qr_code_scanner, size: 28),
              label: Text(
                _monto == 0 ? 'Escanear el vale' : 'Escanear y cobrar ${pesos(_monto)}',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Lo que pasó con el cobro anterior. Se queda en pantalla porque en la caja el siguiente
/// cliente llega antes de que alguien alcance a revisar si el anterior quedó bien.
class _UltimoCobro extends StatelessWidget {
  const _UltimoCobro({required this.respuesta});

  final RespuestaMarca respuesta;

  @override
  Widget build(BuildContext context) {
    final cobrado = respuesta.resultado == ResultadoMarca.valeCobrado;
    final texto = switch (respuesta.resultado) {
      ResultadoMarca.valeCobrado =>
        'Cobrado ${pesos(respuesta.monto ?? 0)}${respuesta.nombre == null ? '' : ' · ${respuesta.nombre}'}',
      ResultadoMarca.valeYaUsado => 'El vale anterior ya se había gastado',
      ResultadoMarca.soloParaAlmuerzo => 'Ese vale sirve solo para el almuerzo',
      ResultadoMarca.valeReservado => 'Ese vale tiene almuerzo reservado',
      ResultadoMarca.vencido => 'Ese vale estaba vencido',
      ResultadoMarca.desactivado => 'Su empresa lo tiene desactivado',
      ResultadoMarca.sinConexion => 'Sin conexión: no se cobró nada',
      _ => 'No se cobró: ticket desconocido',
    };

    return Row(
      children: [
        Icon(cobrado ? Icons.check_circle : Icons.error_outline,
            size: 18, color: cobrado ? const Color(0xFF146C4E) : const Color(0xFFC0392B)),
        const SizedBox(width: 8),
        Expanded(child: Text(texto, style: const TextStyle(fontSize: 13))),
      ],
    );
  }
}

class _Teclado extends StatelessWidget {
  const _Teclado({required this.onDigito, required this.onBorrar});

  final void Function(String) onDigito;
  final VoidCallback onBorrar;

  @override
  Widget build(BuildContext context) {
    const teclas = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '000', '0', '⌫'];

    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.count(
        crossAxisCount: 3,
        childAspectRatio: 1.9,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          for (final t in teclas)
            OutlinedButton(
              onPressed: () => t == '⌫' ? onBorrar() : onDigito(t),
              style: OutlinedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF123528),
              ),
              child: Text(t, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}
