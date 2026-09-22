import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Se actualiza sola, sin depender de una tienda ni de otra aplicación.
///
/// La app pregunta a GitHub cuál es la última publicación, compara con la versión que trae
/// dentro y, si hay una más nueva, la baja y le pide a Android que la instale. Android SIEMPRE
/// muestra su pantalla de confirmación —no hay forma de saltársela sin ser dueño del
/// dispositivo—, así que el mesón toca «instalar» una vez y listo.
class Actualizacion {
  const Actualizacion({required this.version, required this.url, required this.notas});

  /// La versión publicada, como «1.0.25».
  final String version;

  /// De dónde se baja el archivo.
  final String url;

  final String? notas;

  static const _api = 'https://api.github.com/repos/makki-cl/makki-fila/releases/latest';

  /// Qué versión trae la app instalada.
  static Future<String> versionInstalada() async =>
      (await PackageInfo.fromPlatform()).version;

  /// Busca si hay una versión más nueva. Devuelve null si ya está al día o si no hay señal:
  /// quedarse sin actualizar no es un error que valga la pena mostrarle al mesón.
  static Future<Actualizacion?> buscar() async {
    try {
      final r = await http.get(Uri.parse(_api),
          headers: {'Accept': 'application/vnd.github+json'}).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return null;

      final j = _json(r.body);
      final etiqueta = (j['tag_name'] as String? ?? '').replaceFirst('v', '');
      final assets = (j['assets'] as List?) ?? [];
      final apk = assets.cast<Map<String, dynamic>>().where(
          (a) => (a['name'] as String? ?? '').endsWith('.apk'));
      if (etiqueta.isEmpty || apk.isEmpty) return null;

      final actual = await versionInstalada();
      if (!_esMasNueva(etiqueta, actual)) return null;

      return Actualizacion(
        version: etiqueta,
        url: apk.first['browser_download_url'] as String,
        notas: j['body'] as String?,
      );
    } catch (_) {
      return null;
    }
  }

  /// Baja el archivo y se lo entrega a Android para que lo instale.
  ///
  /// [avance] va de 0 a 1: son 65 MB y en el wifi del casino eso se nota; sin una barra, quien
  /// atiende cree que se colgó y lo intenta de nuevo.
  Future<String?> instalar({void Function(double)? avance}) async {
    try {
      final destino = File('${(await getTemporaryDirectory()).path}/makki-$version.apk');

      final peticion = http.Request('GET', Uri.parse(url));
      final respuesta = await http.Client().send(peticion);
      if (respuesta.statusCode != 200) return 'No se pudo bajar (${respuesta.statusCode}).';

      final total = respuesta.contentLength ?? 0;
      var recibido = 0;
      final salida = destino.openWrite();
      await respuesta.stream.map((trozo) {
        recibido += trozo.length;
        if (total > 0) avance?.call(recibido / total);
        return trozo;
      }).pipe(salida);

      final r = await OpenFilex.open(destino.path,
          type: 'application/vnd.android.package-archive');
      if (r.type != ResultType.done) return r.message;
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Compara «1.0.25» con «1.0.9» por número y no por texto: como texto, «9» gana.
  static bool _esMasNueva(String nueva, String actual) {
    List<int> partes(String v) =>
        v.split('.').map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();
    final a = partes(nueva), b = partes(actual);
    for (var i = 0; i < a.length || i < b.length; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  static Map<String, dynamic> _json(String cuerpo) =>
      jsonDecode(cuerpo) as Map<String, dynamic>;
}
