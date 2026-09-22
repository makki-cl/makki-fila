import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:makki_fila/src/api/models.dart';
import 'package:makki_fila/src/app_state.dart';
import 'package:makki_fila/src/data/local_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Lo que de verdad importa del mesón: que la fila siga andando con el wifi caído.
///
/// El servidor de estas pruebas no existe —el puerto 1 no lo escucha nadie— así que cada
/// llamada falla como falla en el casino cuando se cae la red.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object> equipoConDiaBajado({String modo = 'fila'}) => {
        'baseUrl': 'http://127.0.0.1:1',
        'deviceToken': 'mk_de_prueba',
        'operador': 'Raquel',
        'modoMeson': modo,
        'diaCache': jsonEncode({
          'date': '2026-09-22',
          'unitName': 'Casino Bernardino',
          'status': 'publicada',
          'notes': null,
          'options': [
            {'id': 'o1', 'name': 'Cazuela', 'quota': 80, 'reserved': 12},
          ],
          'tickets': [
            {
              'id': 't1', 'code': 'ABC123', 'token': 'tok-ana', 'personName': 'Ana Pérez',
              'area': null, 'clientName': 'Yadran', 'selfManaged': false,
              'optionName': 'Cazuela', 'state': 'vigente', 'consumedUtc': null, 'comment': null,
            },
            {
              'id': 't2', 'code': 'DEF456', 'token': 'tok-luis', 'personName': 'Luis Soto',
              'area': null, 'clientName': 'Sealand', 'selfManaged': false,
              'optionName': 'Cazuela', 'state': 'vigente', 'consumedUtc': null, 'comment': null,
            },
          ],
        }),
      };

  test('sin señal se sirve contra la copia y la marca queda encolada', () async {
    SharedPreferences.setMockInitialValues(equipoConDiaBajado());
    final estado = AppState(LocalStore());
    await estado.iniciar();

    // La copia bajada sobrevive a que el servidor no conteste.
    expect(estado.dia, isNotNull);
    expect(estado.dia!.tickets, hasLength(2));

    final r = await estado.marcar('tok-ana');
    expect(r.resultado, ResultadoMarca.ok);
    expect(r.ticket!.persona, 'Ana Pérez');
    expect(estado.pendientes, 1);

    estado.dispose();
  });

  test('lo marcado sin señal sobrevive a que se cierre la app', () async {
    SharedPreferences.setMockInitialValues(equipoConDiaBajado());
    final primera = AppState(LocalStore());
    await primera.iniciar();
    await primera.marcar('tok-ana');
    primera.dispose();

    // Se abre de nuevo: ni la cola ni lo servido se pierden, y el intento de subirla falla
    // sin borrarla.
    final segunda = AppState(LocalStore());
    await segunda.iniciar();
    expect(segunda.pendientes, 1);
    expect(
      segunda.dia!.tickets.firstWhere((t) => t.token == 'tok-ana').estado,
      EstadoTicket.servido,
    );
    segunda.dispose();
  });

  test('el mismo ticket dos veces no se sirve dos veces', () async {
    SharedPreferences.setMockInitialValues(equipoConDiaBajado());
    final estado = AppState(LocalStore());
    await estado.iniciar();

    await estado.marcar('tok-luis');
    final segunda = await estado.marcar('tok-luis');

    expect(segunda.resultado, ResultadoMarca.yaConsumido);
    expect(estado.pendientes, 1, reason: 'la segunda no puede encolar otra marca');
    estado.dispose();
  });

  test('un código que no está en la copia no pasa por sin conexión', () async {
    SharedPreferences.setMockInitialValues(equipoConDiaBajado());
    final estado = AppState(LocalStore());
    await estado.iniciar();

    final r = await estado.marcar('tok-que-no-existe');
    expect(r.resultado, ResultadoMarca.fueraDeLaCopia);
    expect(estado.pendientes, 0);
    estado.dispose();
  });

  test('la caja sin señal no cobra nada', () async {
    SharedPreferences.setMockInitialValues(equipoConDiaBajado(modo: 'caja'));
    final estado = AppState(LocalStore());
    await estado.iniciar();

    final r = await estado.marcar('tok-ana', monto: 3000);
    expect(r.resultado, ResultadoMarca.sinConexion);
    expect(estado.pendientes, 0, reason: 'un cobro a ciegas no se encola');
    estado.dispose();
  });

  test('el código se reconoce dictado, con guion y desde la URL del QR', () async {
    SharedPreferences.setMockInitialValues(equipoConDiaBajado());
    final estado = AppState(LocalStore());
    await estado.iniciar();

    expect((await estado.marcar('abc-123')).ticket?.persona, 'Ana Pérez');
    expect((await estado.marcar('https://casino.makki.cl/t/tok-luis')).ticket?.persona,
        'Luis Soto');
    estado.dispose();
  });
}
