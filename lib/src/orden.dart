import 'api/models.dart';

/// Cómo se ordena la lista del día en el mesón.
enum OrdenLista {
  /// Todos juntos por nombre. Sirve cuando llega gente suelta y solo se sabe cómo se llama.
  alfabetico,

  /// Agrupados por empresa y, dentro de cada una, por nombre. Es el orden en que se factura
  /// y el que usa quien pasa lista por empresa.
  empresa,

  /// Por hora: los servidos del último al primero, y los que faltan por orden de llegada.
  /// Sirve para dos preguntas distintas —«¿pasé o no?» y «¿quién se anotó primero?»— y en la
  /// lista de por servir es la única que importa.
  cronologico,
}

/// Encabezado de un grupo de la lista.
class GrupoDeEmpresa {
  const GrupoDeEmpresa(this.empresa, this.cuantos);

  final String empresa;
  final int cuantos;
}

/// Ordena los anotados y, si corresponde, intercala los encabezados de empresa.
///
/// Devuelve una lista mezclada de [GrupoDeEmpresa] y [Ticket] porque así se dibuja de una
/// pasada: el mesón necesita ver dónde empieza cada empresa sin perder el desplazamiento.
List<Object> ordenar(List<Ticket> tickets, OrdenLista orden) {
  // Se compara sin distinguir mayúsculas ni tildes: «Ávila» tiene que quedar entre «Avendaño»
  // y «Ayala», no al final de todo, que es donde lo dejaría comparar por código de carácter.
  int porNombre(Ticket a, Ticket b) => _clave(a.persona).compareTo(_clave(b.persona));

  if (orden == OrdenLista.alfabetico) {
    final solos = [...tickets]..sort(porNombre);
    return solos;
  }

  if (orden == OrdenLista.cronologico) {
    // Servidos primero, del más reciente al más viejo: así se contesta «¿pasé o no?» mirando
    // arriba. Los que todavía no pasan van después POR ORDEN DE LLEGADA —la hora en que se
    // anotaron—, que es el orden en que corresponde atenderlos; antes caían al final por
    // nombre y «cronológico» se veía igual que «alfabético». Sin esa hora —un día bajado por
    // una versión anterior— se ordenan por nombre, que es lo que había.
    final porHora = [...tickets]..sort((a, b) {
        final ha = a.consumidoUtc, hb = b.consumidoUtc;
        if (ha != null && hb != null) return hb.compareTo(ha);
        if (ha != null) return -1;
        if (hb != null) return 1;

        final ca = a.creadoUtc, cb = b.creadoUtc;
        if (ca != null && cb != null) {
          final porLlegada = ca.compareTo(cb);
          if (porLlegada != 0) return porLlegada;
        }
        return porNombre(a, b);
      });
    return porHora;
  }

  final ordenados = [...tickets]
    ..sort((a, b) {
      final empresas = _clave(_empresaDe(a)).compareTo(_clave(_empresaDe(b)));
      return empresas != 0 ? empresas : porNombre(a, b);
    });

  final filas = <Object>[];
  String? actual;
  for (final t in ordenados) {
    final empresa = _empresaDe(t);
    if (empresa != actual) {
      actual = empresa;
      filas.add(GrupoDeEmpresa(
        empresa,
        ordenados.where((x) => _empresaDe(x) == empresa).length,
      ));
    }
    filas.add(t);
  }
  return filas;
}

/// Quien se anotó por el enlace sin elegir empresa igual tiene que aparecer, y en un grupo
/// propio: si se le pusiera una empresa cualquiera, alguien terminaría facturándolo.
String _empresaDe(Ticket t) =>
    (t.empresa == null || t.empresa!.trim().isEmpty) ? 'Sin empresa' : t.empresa!.trim();

const _conTilde = 'áàäâãéèëêíìïîóòöôõúùüûñç';
const _sinTilde = 'aaaaaeeeeiiiiooooouuuunc';

String _clave(String texto) {
  final buf = StringBuffer();
  for (final c in texto.toLowerCase().runes) {
    final ch = String.fromCharCode(c);
    final i = _conTilde.indexOf(ch);
    buf.write(i >= 0 ? _sinTilde[i] : ch);
  }
  return buf.toString();
}
