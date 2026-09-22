import 'package:flutter_test/flutter_test.dart';
import 'package:makki_fila/src/api/models.dart';
import 'package:makki_fila/src/orden.dart';

Ticket persona(String nombre, String? empresa, {DateTime? servido}) => Ticket(
      id: nombre, codigo: 'AAA111', token: nombre, persona: nombre, area: null,
      empresa: empresa, acreditada: false, opcion: 'Cazuela',
      estado: servido == null ? EstadoTicket.vigente : EstadoTicket.servido,
      consumidoUtc: servido, comentario: null,
    );

void main() {
  final gente = [
    persona('Zoila Vera', 'Yadran'),
    persona('ávila, Rosa', 'Sealand'),
    persona('Ana Pérez', 'Yadran'),
    persona('Bruno Díaz', null),
  ];

  test('alfabético ignora tildes y mayúsculas', () {
    final filas = ordenar(gente, OrdenLista.alfabetico).cast<Ticket>();
    expect(filas.map((t) => t.persona),
        ['Ana Pérez', 'ávila, Rosa', 'Bruno Díaz', 'Zoila Vera']);
  });

  test('por empresa agrupa, cuenta y ordena por nombre dentro del grupo', () {
    final filas = ordenar(gente, OrdenLista.empresa);

    final encabezados = filas.whereType<GrupoDeEmpresa>().toList();
    expect(encabezados.map((g) => g.empresa), ['Sealand', 'Sin empresa', 'Yadran']);
    expect(encabezados.firstWhere((g) => g.empresa == 'Yadran').cuantos, 2);

    // Dentro de Yadran, Ana antes que Zoila.
    final yadran = filas.sublist(filas.indexWhere(
        (f) => f is GrupoDeEmpresa && f.empresa == 'Yadran'));
    expect(yadran.whereType<Ticket>().map((t) => t.persona), ['Ana Pérez', 'Zoila Vera']);
  });

  test('quien no eligió empresa igual aparece, en su propio grupo', () {
    final filas = ordenar(gente, OrdenLista.empresa);
    final sinEmpresa = filas.whereType<GrupoDeEmpresa>().firstWhere(
        (g) => g.empresa == 'Sin empresa');
    expect(sinEmpresa.cuantos, 1);
  });

  group('cronológico', () {
    final t = DateTime.utc(2026, 9, 22, 15);
    final fila = [
      persona('Primero', 'Yadran', servido: t),
      persona('Tercero', 'Yadran', servido: t.add(const Duration(minutes: 20))),
      persona('No pasó', 'Sealand'),
      persona('Segundo', 'Sealand', servido: t.add(const Duration(minutes: 10))),
    ];

    test('el último servido va arriba', () {
      final r = ordenar(fila, OrdenLista.cronologico).cast<Ticket>();
      expect(r.take(3).map((x) => x.persona), ['Tercero', 'Segundo', 'Primero']);
    });

    test('los que no han pasado quedan al final, no se pierden', () {
      final r = ordenar(fila, OrdenLista.cronologico).cast<Ticket>();
      expect(r.last.persona, 'No pasó');
      expect(r, hasLength(4));
    });
  });
}
