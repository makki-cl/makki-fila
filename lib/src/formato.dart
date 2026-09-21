/// Plata como se escribe en Chile: punto para los miles y sin decimales. Los tickets son
/// siempre montos redondos, así que no hay nada que redondear a la vista del mesón.
String pesos(num valor) {
  final entero = valor.round().abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < entero.length; i++) {
    if (i > 0 && (entero.length - i) % 3 == 0) buf.write('.');
    buf.write(entero[i]);
  }
  return '${valor < 0 ? '-' : ''}\$$buf';
}
