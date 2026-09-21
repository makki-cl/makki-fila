import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../api/models.dart';

/// Lo que la app guarda en el equipo: el token, la copia del día y la cola de marcas que
/// todavía no llegan al servidor. Es deliberadamente simple —preferencias con JSON— porque
/// el volumen de un día son cientos de filas, no miles.
class LocalStore {
  static const _kBaseUrl = 'baseUrl';
  static const _kToken = 'deviceToken';
  static const _kOperador = 'operador';
  static const _kDia = 'diaCache';
  static const _kCola = 'colaPendiente';
  static const _kModo = 'modoMeson';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  Future<String?> baseUrl() async => (await _prefs).getString(_kBaseUrl);
  Future<void> guardarBaseUrl(String v) async => (await _prefs).setString(_kBaseUrl, v);

  Future<String?> token() async => (await _prefs).getString(_kToken);
  Future<void> guardarToken(String v) async => (await _prefs).setString(_kToken, v);

  Future<String> operador() async => (await _prefs).getString(_kOperador) ?? '';
  Future<void> guardarOperador(String v) async => (await _prefs).setString(_kOperador, v);

  /// En qué está el equipo: la fila del almuerzo o la caja. Se guarda porque un mismo turno
  /// se pasa entero en uno de los dos, y volver a elegirlo en cada reinicio invita al error.
  Future<String?> modo() async => (await _prefs).getString(_kModo);
  Future<void> guardarModo(String v) async => (await _prefs).setString(_kModo, v);

  /// Borra el enrolamiento. Se usa al revocar el equipo o al reinstalar.
  Future<void> olvidarTodo() async {
    final p = await _prefs;
    await p.remove(_kToken);
    await p.remove(_kDia);
    await p.remove(_kCola);
  }

  Future<DiaDeTrabajo?> diaGuardado() async {
    final texto = (await _prefs).getString(_kDia);
    if (texto == null) return null;
    try {
      final j = jsonDecode(texto) as Map<String, dynamic>;
      final dia = DiaDeTrabajo.desdeJson(j);
      return dia;
    } catch (_) {
      // Una copia corrupta no puede dejar la app inservible: se descarta y se baja de nuevo.
      return null;
    }
  }

  Future<void> guardarDia(DiaDeTrabajo dia) async =>
      (await _prefs).setString(_kDia, jsonEncode(dia.aJson()));

  Future<List<MarcaPendiente>> cola() async {
    final texto = (await _prefs).getString(_kCola);
    if (texto == null) return [];
    try {
      return (jsonDecode(texto) as List)
          .map((m) => MarcaPendiente.desdeJson(m as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> guardarCola(List<MarcaPendiente> marcas) async => (await _prefs)
      .setString(_kCola, jsonEncode(marcas.map((m) => m.aJson()).toList()));
}
