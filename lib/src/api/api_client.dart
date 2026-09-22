import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// Cliente de la API de la fila. Toda petición va con el token del dispositivo: acá no hay
/// usuario ni clave, porque el equipo lo usan varios turnos y pedir credenciales en cada
/// almuerzo detiene la fila.
class ApiClient {
  ApiClient({required this.baseUrl, this.token});

  final String baseUrl;
  final String? token;

  static const _tiempoLimite = Duration(seconds: 12);

  Map<String, String> get _cabeceras => {
        'Content-Type': 'application/json',
        if (token != null) 'X-Makki-Device': token!,
      };

  Uri _uri(String ruta) => Uri.parse('$baseUrl$ruta');

  /// Canjea el código de enrolamiento por el token del dispositivo. El token se entrega una
  /// sola vez: si se pierde, hay que pedir un código nuevo desde el panel.
  static Future<String> enrolar({
    required String baseUrl,
    required String codigo,
    required String infoEquipo,
  }) async {
    final r = await http
        .post(
          Uri.parse('$baseUrl/api/line/enroll'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'code': codigo, 'deviceInfo': infoEquipo}),
        )
        .timeout(_tiempoLimite);

    final cuerpo = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    if (r.statusCode != 200) {
      throw Exception(cuerpo['error'] as String? ?? 'No se pudo enrolar el equipo.');
    }
    return cuerpo['token'] as String;
  }

  Future<Sesion> sesion() async {
    final r = await http.get(_uri('/api/line/session'), headers: _cabeceras).timeout(_tiempoLimite);
    if (r.statusCode != 200) throw Exception('Sesión rechazada (${r.statusCode}).');
    return Sesion.desdeJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  /// Baja el día completo. Es la única descarga: después la app trabaja contra esta copia.
  Future<DiaDeTrabajo> dia() async {
    final r = await http.get(_uri('/api/line/today'), headers: _cabeceras).timeout(_tiempoLimite);
    if (r.statusCode != 200) throw Exception('No se pudo bajar el día (${r.statusCode}).');
    return DiaDeTrabajo.desdeJson(jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>);
  }

  /// Marca un ticket. [enCaja] cambia lo que el servidor registra: en la caja el ticket se
  /// gasta en otros productos, no en el almuerzo, y el informe del mes tiene que separarlos.
  /// [monto] es el total de la compra; si supera el valor del ticket, el servidor cobra solo
  /// hasta ahí y la diferencia la paga la persona.
  Future<RespuestaMarca> marcar(String ticket, String operador,
      {DateTime? cuandoUtc, bool enCaja = false, num? monto}) async {
    final r = await http
        .post(
          _uri('/api/line/consume'),
          headers: _cabeceras,
          body: jsonEncode({
            'ticket': ticket,
            'operator': operador,
            if (cuandoUtc != null) 'atUtc': cuandoUtc.toIso8601String(),
            if (enCaja) 'enCaja': true,
            if (monto != null) 'monto': monto,
          }),
        )
        .timeout(_tiempoLimite);

    if (r.statusCode != 200) throw Exception('Error del servidor (${r.statusCode}).');

    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final t = j['ticket'] == null ? null : Ticket.desdeJson(j['ticket'] as Map<String, dynamic>);
    return RespuestaMarca.desdeJson(j, _interpretar(j['status'] as String?), t);
  }

  /// Envía de una vez lo marcado sin señal, con la hora real de cada marca.
  ///
  /// Devuelve cuántas entraron y cuántas el servidor no pudo aplicar. Lo segundo importa: una
  /// marca rechazada —el ticket estaba anulado, o era de otro día— se perdería en silencio si
  /// solo se contaran las que llegaron, y quien atendió nunca sabría que ese almuerzo no quedó
  /// registrado.
  Future<({int aplicadas, int rechazadas})> sincronizar(List<MarcaPendiente> marcas) async {
    if (marcas.isEmpty) return (aplicadas: 0, rechazadas: 0);
    final r = await http
        .post(
          _uri('/api/line/sync'),
          headers: _cabeceras,
          body: jsonEncode({'marks': marcas.map((m) => m.aJson()).toList()}),
        )
        .timeout(const Duration(seconds: 30));

    if (r.statusCode != 200) throw Exception('No se pudo sincronizar (${r.statusCode}).');
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;

    const buenos = {'Ok', 'AlreadyConsumed'};
    final detalle = (j['results'] as List?) ?? [];
    final rechazadas = detalle
        .where((d) => !buenos.contains((d as Map<String, dynamic>)['status'] as String? ?? ''))
        .length;

    return (
      aplicadas: ((j['applied'] as num?)?.toInt() ?? 0) - rechazadas,
      rechazadas: rechazadas,
    );
  }

  /// Traduce el estado que manda el servidor. Lo que no se reconoce se trata como «no
  /// existe», que es el mensaje más seguro: nunca hace servir un almuerzo por equivocación.
  static ResultadoMarca _interpretar(String? estado) => switch (estado) {
        'Ok' => ResultadoMarca.ok,
        'AlreadyConsumed' => ResultadoMarca.yaConsumido,
        'Cancelled' => ResultadoMarca.anulado,
        'WrongDay' => ResultadoMarca.otroDia,
        'Desactivado' => ResultadoMarca.desactivado,
        'ValeCobrado' => ResultadoMarca.valeCobrado,
        'ValeYaUsado' => ResultadoMarca.valeYaUsado,
        'ValeReservado' => ResultadoMarca.valeReservado,
        'SinTicket' => ResultadoMarca.sinTicket,
        'SoloParaAlmuerzo' => ResultadoMarca.soloParaAlmuerzo,
        'Vencido' => ResultadoMarca.vencido,
        _ => ResultadoMarca.noExiste,
      };
}
