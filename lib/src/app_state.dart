import 'package:flutter/foundation.dart';

import 'api/api_client.dart';
import 'api/models.dart';
import 'data/local_store.dart';

/// Estado de la app. Manda la copia local: se marca contra ella y el servidor se entera
/// después. Así la fila nunca se detiene porque el wifi del casino se cayó.
class AppState extends ChangeNotifier {
  AppState(this._store);

  final LocalStore _store;

  String? baseUrl;
  String? _token;
  String operador = '';
  Sesion? sesion;
  DiaDeTrabajo? dia;
  List<MarcaPendiente> cola = [];
  bool cargando = false;
  String? error;

  bool get enrolado => _token != null && baseUrl != null;
  int get pendientes => cola.length;

  ApiClient get _api => ApiClient(baseUrl: baseUrl!, token: _token);

  Future<void> iniciar() async {
    baseUrl = await _store.baseUrl();
    _token = await _store.token();
    operador = await _store.operador();
    cola = await _store.cola();
    dia = await _store.diaGuardado();
    notifyListeners();

    if (enrolado) {
      await sincronizar();
      await refrescar();
    }
  }

  Future<void> enrolar(String url, String codigo, String infoEquipo) async {
    cargando = true;
    error = null;
    notifyListeners();
    try {
      final limpia = url.trim().replaceAll(RegExp(r'/+$'), '');
      final token = await ApiClient.enrolar(
        baseUrl: limpia,
        codigo: codigo.trim().toUpperCase().replaceAll('-', ''),
        infoEquipo: infoEquipo,
      );
      await _store.guardarBaseUrl(limpia);
      await _store.guardarToken(token);
      baseUrl = limpia;
      _token = token;
      await refrescar();
    } catch (e) {
      error = _mensaje(e);
    } finally {
      cargando = false;
      notifyListeners();
    }
  }

  Future<void> guardarOperador(String nombre) async {
    operador = nombre.trim();
    await _store.guardarOperador(operador);
    notifyListeners();
  }

  /// Baja el día de nuevo. Si no hay red, se queda con la copia que ya tenía.
  Future<void> refrescar() async {
    if (!enrolado) return;
    cargando = true;
    notifyListeners();
    try {
      sesion = await _api.sesion();
      final bajado = await _api.dia();
      // Las marcas que aún no llegaron al servidor se vuelven a aplicar sobre la copia nueva,
      // si no el ticket reaparecería como pendiente y alguien lo serviría dos veces.
      for (final m in cola) {
        final t = _buscarEn(bajado, m.ticket);
        if (t != null && t.estado == EstadoTicket.vigente) {
          t.estado = EstadoTicket.servido;
          t.consumidoUtc = m.cuandoUtc;
        }
      }
      dia = bajado;
      await _store.guardarDia(bajado);
      error = null;
    } catch (e) {
      error = _mensaje(e);
    } finally {
      cargando = false;
      notifyListeners();
    }
  }

  /// Marca un ticket. Intenta el servidor; si no hay red, lo deja en la cola y sigue.
  Future<(ResultadoMarca, Ticket?)> marcar(String lectura) async {
    final local = _buscarEn(dia, lectura);

    // Lo que ya sabemos por la copia local se responde al tiro: es el caso más común en la
    // fila y no tiene sentido esperar al servidor para decir «este ticket ya se sirvió».
    if (local != null && local.estado == EstadoTicket.anulado) {
      return (ResultadoMarca.anulado, local);
    }
    if (local != null && local.estado == EstadoTicket.servido) {
      return (ResultadoMarca.yaConsumido, local);
    }

    try {
      final (resultado, ticket) = await _api.marcar(lectura, _operadorOEquipo);
      if (resultado == ResultadoMarca.ok && local != null) {
        local.estado = EstadoTicket.servido;
        local.consumidoUtc = ticket?.consumidoUtc ?? DateTime.now().toUtc();
        await _store.guardarDia(dia!);
      }
      notifyListeners();
      return (resultado, ticket ?? local);
    } catch (_) {
      // Sin señal: se marca localmente y se encola. La hora que queda es esta, la real.
      if (local == null) {
        // Se distingue el caso: si hay copia del día bajada, el problema no es la red —
        // ese ticket no está en la lista. Decir "sin conexión" haría que el mesón deje
        // pasar a alguien pensando que es culpa del wifi.
        return (dia == null ? ResultadoMarca.sinConexion : ResultadoMarca.fueraDeLaCopia, null);
      }

      local.estado = EstadoTicket.servido;
      local.consumidoUtc = DateTime.now().toUtc();
      cola = [
        ...cola,
        MarcaPendiente(
          ticket: local.token.isNotEmpty ? local.token : local.codigo,
          operador: _operadorOEquipo,
          cuandoUtc: local.consumidoUtc!,
        ),
      ];
      await _store.guardarDia(dia!);
      await _store.guardarCola(cola);
      notifyListeners();
      return (ResultadoMarca.ok, local);
    }
  }

  Future<int> sincronizar() async {
    if (!enrolado || cola.isEmpty) return 0;
    try {
      final aplicadas = await _api.sincronizar(cola);
      cola = [];
      await _store.guardarCola(cola);
      notifyListeners();
      return aplicadas;
    } catch (e) {
      error = _mensaje(e);
      notifyListeners();
      return 0;
    }
  }

  Future<void> desenrolar() async {
    await _store.olvidarTodo();
    _token = null;
    dia = null;
    cola = [];
    sesion = null;
    notifyListeners();
  }

  /// Hora en que se bajó la copia con la que se está trabajando.
  String get horaDeLaCopia {
    final b = dia?.bajadoUtc.toLocal();
    if (b == null) return '—';
    return '${b.hour.toString().padLeft(2, '0')}:${b.minute.toString().padLeft(2, '0')}';
  }

  String get _operadorOEquipo => operador.isNotEmpty ? operador : (sesion?.deviceName ?? 'mesón');

  /// Busca el ticket por token, por código o por la URL completa que trae el QR.
  Ticket? _buscarEn(DiaDeTrabajo? dia, String lectura) {
    if (dia == null) return null;
    var texto = lectura.trim();
    if (texto.contains('/')) texto = texto.substring(texto.lastIndexOf('/') + 1);
    final codigo = texto.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

    for (final t in dia.tickets) {
      if (t.token == texto || t.codigo == codigo) return t;
    }
    return null;
  }

  static String _mensaje(Object e) {
    final texto = e.toString().replaceFirst('Exception: ', '');
    if (texto.contains('SocketException') || texto.contains('TimeoutException')) {
      return 'Sin conexión con el servidor.';
    }
    return texto;
  }
}
