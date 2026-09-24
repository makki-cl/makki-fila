import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show Size;

import 'api/api_client.dart';
import 'api/models.dart';
import 'data/local_store.dart';
import 'orden.dart';

/// Resoluciones que se le pueden pedir a la cámara.
///
/// Existe esta lista porque hay tablets —las rugerizadas baratas sobre todo— cuyo driver
/// entrega el cuadro con un ancho de fila que no calza con la resolución que dice tener, y la
/// pantalla muestra bandas de colores en vez de la imagen. Cambiar la resolución lo arregla,
/// pero cuál funciona depende del equipo, así que se elige en el equipo y no en el código:
/// nadie puede esperar un APK nuevo con la fila formada.
enum ResolucionCamara {
  automatica('Automática', null),
  media('1280 × 720', Size(1280, 720)),
  alta('1920 × 1080', Size(1920, 1080)),
  baja('640 × 480', Size(640, 480));

  const ResolucionCamara(this.etiqueta, this.tamano);

  final String etiqueta;
  final Size? tamano;
}

/// En qué está atendiendo el equipo.
///
/// No es un detalle de pantalla: en la fila se entrega el almuerzo del día y en la caja se
/// gasta el ticket en otros productos. El informe del mes los separa, así que el equipo tiene
/// que declarar en cuál está antes de marcar.
enum ModoMeson { fila, caja }

/// Estado de la app. Manda la copia local: se marca contra ella y el servidor se entera
/// después. Así la fila nunca se detiene porque el wifi del casino se cayó.
class AppState extends ChangeNotifier {
  AppState(this._store);

  final LocalStore _store;

  String? baseUrl;
  String? _token;
  String operador = '';
  ModoMeson modo = ModoMeson.fila;
  OrdenLista orden = OrdenLista.alfabetico;
  ResolucionCamara resolucion = ResolucionCamara.automatica;
  bool camaraFrontal = false;
  Sesion? sesion;
  DiaDeTrabajo? dia;
  List<MarcaPendiente> cola = [];
  bool cargando = false;
  String? error;

  Timer? _reintentos;
  int _vueltas = 0;

  bool get enrolado => _token != null && baseUrl != null;
  int get pendientes => cola.length;

  ApiClient get _api => ApiClient(baseUrl: baseUrl!, token: _token);

  Future<void> iniciar() async {
    baseUrl = await _store.baseUrl();
    _token = await _store.token();
    operador = await _store.operador();
    modo = await _store.modo() == ModoMeson.caja.name ? ModoMeson.caja : ModoMeson.fila;
    final ordenGuardado = await _store.orden();
    orden = OrdenLista.values.firstWhere((o) => o.name == ordenGuardado,
        orElse: () => OrdenLista.alfabetico);
    final guardada = await _store.resolucion();
    resolucion = ResolucionCamara.values.firstWhere((r) => r.name == guardada,
        orElse: () => ResolucionCamara.automatica);
    camaraFrontal = await _store.camaraFrontal();
    cola = await _store.cola();
    dia = await _store.diaGuardado();
    notifyListeners();

    if (enrolado) {
      await sincronizar();
      await refrescar();
    }
    _arrancarReintentos();
  }

  /// Reintentos en segundo plano.
  ///
  /// La tablet vive en un mesón, no en una mano: nadie está mirando si volvió el wifi. Sin
  /// esto, las marcas hechas sin señal se quedan en la cola hasta que a alguien se le ocurre
  /// tocar el botón de subir, y la copia del día envejece mientras la gente se sigue anotando.
  void _arrancarReintentos() {
    _reintentos?.cancel();
    _reintentos = Timer.periodic(const Duration(minutes: 1), (_) async {
      if (!enrolado) return;
      if (cola.isNotEmpty) await sincronizar(silencioso: true);

      // La copia se renueva más espaciada: durante el servicio la gente sigue anotándose, pero
      // bajar el día entero cada minuto es gasto sin necesidad.
      _vueltas++;
      if (_vueltas % 5 == 0 && !cargando) await refrescar(silencioso: true);
    });
  }

  @override
  void dispose() {
    _reintentos?.cancel();
    super.dispose();
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

  Future<void> cambiarResolucion(ResolucionCamara nueva) async {
    resolucion = nueva;
    await _store.guardarResolucion(nueva.name);
    notifyListeners();
  }

  Future<void> cambiarCamara(bool frontal) async {
    camaraFrontal = frontal;
    await _store.guardarCamaraFrontal(frontal);
    notifyListeners();
  }

  Future<void> cambiarOrden(OrdenLista nuevo) async {
    orden = nuevo;
    await _store.guardarOrden(nuevo.name);
    notifyListeners();
  }

  Future<void> cambiarModo(ModoMeson nuevo) async {
    modo = nuevo;
    await _store.guardarModo(nuevo.name);
    notifyListeners();
  }

  Future<void> guardarOperador(String nombre) async {
    operador = nombre.trim();
    await _store.guardarOperador(operador);
    notifyListeners();
  }

  /// Baja el día de nuevo. Si no hay red, se queda con la copia que ya tenía.
  ///
  /// [silencioso] es para los reintentos automáticos: no mueve el indicador de carga ni pinta
  /// un error en rojo. Sin eso, una tablet sin señal mostraría el aviso solo porque pasaron
  /// cinco minutos, y quien atiende aprendería a ignorarlo.
  Future<void> refrescar({bool silencioso = false}) async {
    if (!enrolado) return;
    if (!silencioso) {
      cargando = true;
      notifyListeners();
    }
    try {
      sesion = await _api.sesion();
      final bajado = await _api.dia();
      // Las marcas que aún no llegaron al servidor se vuelven a aplicar sobre la copia nueva,
      // si no el ticket reaparecería como pendiente y alguien lo serviría dos veces.
      for (final m in cola) {
        final t = _buscarEn(bajado, m.ticket);
        if (t != null && t.estado != EstadoTicket.anulado) {
          t.estado = EstadoTicket.servido;
          t.consumidoUtc = m.cuandoUtc;
        }
      }
      dia = bajado;
      await _store.guardarDia(bajado);
      error = null;
    } catch (e) {
      if (!silencioso) error = _mensaje(e);
    } finally {
      cargando = false;
      notifyListeners();
    }
  }

  /// Marca un ticket.
  ///
  /// En la fila manda la copia local y, si no hay señal, la marca se encola: el almuerzo ya
  /// está cocinado y detener la fila por el wifi no arregla nada.
  ///
  /// En la caja es al revés. Un vale no viene en la copia del día —no cuelga de ninguna
  /// minuta— así que sin servidor no hay forma de saber si está vigente o ya se gastó, y
  /// cobrarlo a ciegas sería entregar productos contra un ticket que quizá no existe. Sin
  /// señal, la caja cobra en efectivo.
  /// Anula una reserva desde la lista del mesón.
  ///
  /// Exige señal a propósito: a diferencia de marcar, anular no se puede encolar para
  /// después. Entre que se pide y se envía, la persona puede haber pasado por el otro equipo,
  /// y una anulación aplicada a ciegas le quita un almuerzo que ya se comió.
  Future<RespuestaAnular> anular(Ticket ticket) async {
    final credencial = ticket.token.isNotEmpty ? ticket.token : ticket.codigo;

    try {
      final r = await _api.anular(credencial, _operadorOEquipo);

      if (r.resultado == ResultadoAnular.ok || r.resultado == ResultadoAnular.yaAnulada) {
        ticket.estado = EstadoTicket.anulado;
        if (dia != null) await _store.guardarDia(dia!);
        notifyListeners();
      }

      // Si el servidor dice que ya pasó por la fila, la copia local estaba atrasada: se
      // corrige en pantalla antes de que alguien lo intente de nuevo.
      if (r.resultado == ResultadoAnular.yaServida) {
        ticket.estado = EstadoTicket.servido;
        if (dia != null) await _store.guardarDia(dia!);
        notifyListeners();
      }

      return r;
    } catch (_) {
      return const RespuestaAnular(ResultadoAnular.sinConexion);
    }
  }

  Future<RespuestaMarca> marcar(String lectura, {num? monto}) async {
    if (modo == ModoMeson.caja) {
      try {
        return await _api.marcar(lectura, _operadorOEquipo, enCaja: true, monto: monto);
      } catch (_) {
        return const RespuestaMarca(ResultadoMarca.sinConexion);
      }
    }

    final local = _buscarEn(dia, lectura);

    // Lo que ya sabemos por la copia local se responde al tiro: es el caso más común en la
    // fila y no tiene sentido esperar al servidor para decir «este ticket ya se sirvió».
    if (local != null && local.estado == EstadoTicket.anulado) {
      return RespuestaMarca(ResultadoMarca.anulado, ticket: local);
    }
    if (local != null && local.estado == EstadoTicket.servido) {
      return RespuestaMarca(ResultadoMarca.yaConsumido, ticket: local);
    }

    try {
      final r = await _api.marcar(lectura, _operadorOEquipo);
      if (r.resultado == ResultadoMarca.ok && local != null) {
        local.estado = EstadoTicket.servido;
        local.consumidoUtc = r.ticket?.consumidoUtc ?? DateTime.now().toUtc();
        await _store.guardarDia(dia!);
      }
      notifyListeners();
      if (r.ticket != null || local == null) return r;
      return RespuestaMarca(r.resultado,
          ticket: local, persona: r.persona, monto: r.monto, valor: r.valor);
    } catch (_) {
      // Sin señal: se marca localmente y se encola. La hora que queda es esta, la real.
      if (local == null) {
        // Se distingue el caso: si hay copia del día bajada, el problema no es la red —
        // ese ticket no está en la lista. Decir "sin conexión" haría que el mesón deje
        // pasar a alguien pensando que es culpa del wifi.
        return RespuestaMarca(
            dia == null ? ResultadoMarca.sinConexion : ResultadoMarca.fueraDeLaCopia);
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
      return RespuestaMarca(ResultadoMarca.ok, ticket: local);
    }
  }

  /// Manda al servidor lo que se marcó sin señal.
  ///
  /// La cola se vacía solo si el servidor respondió: si no hay red, se queda entera para el
  /// siguiente intento. Lo que el servidor rechazó también se saca —reintentarlo daría el
  /// mismo rechazo para siempre— pero se informa, porque alguien tiene que saber que ese
  /// almuerzo no quedó registrado.
  /// Anota a alguien en el mesón. Sin señal no se puede: el cupo vive en el servidor y
  /// anotar a ciegas dos veces la misma ración es cocinar de menos.
  Future<RespuestaAnotar> anotar({
    required String menuItemId,
    required String nombre,
    String? empresaId,
    String? otraEmpresa,
    String? correo,
    bool paraLlevar = false,
    bool sobrecupo = false,
  }) async {
    if (!enrolado) return const RespuestaAnotar(ResultadoAnotar.sinConexion);
    try {
      final r = await _api.anotar(
        menuItemId: menuItemId,
        nombre: nombre,
        empresaId: empresaId,
        otraEmpresa: otraEmpresa,
        correo: correo,
        paraLlevar: paraLlevar,
        sobrecupo: sobrecupo,
        operador: _operadorOEquipo,
      );
      if (r.resultado == ResultadoAnotar.ok) await refrescar(silencioso: true);
      return r;
    } catch (_) {
      return const RespuestaAnotar(ResultadoAnotar.sinConexion);
    }
  }

  Future<({int aplicadas, int rechazadas})> sincronizar({bool silencioso = false}) async {
    if (!enrolado || cola.isEmpty) return (aplicadas: 0, rechazadas: 0);
    try {
      final resultado = await _api.sincronizar(cola);
      cola = [];
      await _store.guardarCola(cola);
      notifyListeners();
      return resultado;
    } catch (e) {
      if (!silencioso) error = _mensaje(e);
      notifyListeners();
      return (aplicadas: 0, rechazadas: 0);
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

/// Cómo se le cuenta al mesón lo que pasó al subir la cola.
String mensajeDeSincronia(({int aplicadas, int rechazadas}) r) {
  if (r.aplicadas == 0 && r.rechazadas == 0) return 'Sigue sin conexión';
  if (r.rechazadas == 0) return '${r.aplicadas} marca(s) enviadas';
  if (r.aplicadas == 0) {
    return 'El servidor rechazó ${r.rechazadas} marca(s): revísalas en el panel';
  }
  return '${r.aplicadas} enviadas · ${r.rechazadas} rechazadas, revísalas en el panel';
}
