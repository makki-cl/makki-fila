/// Modelos que viajan entre la app y el servidor. Son de solo lectura: la app no inventa
/// datos, solo refleja lo que bajó y encola lo que marcó.
library;

class Sesion {
  const Sesion({required this.deviceName, required this.unitName});

  final String deviceName;
  final String unitName;

  factory Sesion.desdeJson(Map<String, dynamic> json) {
    final d = json['device'] as Map<String, dynamic>;
    return Sesion(
      deviceName: d['name'] as String? ?? '',
      unitName: d['unitName'] as String? ?? '',
    );
  }
}

class OpcionMenu {
  const OpcionMenu({
    required this.id,
    required this.nombre,
    required this.cupo,
    required this.tomados,
  });

  final String id;
  final String nombre;
  final int cupo;
  final int tomados;

  factory OpcionMenu.desdeJson(Map<String, dynamic> j) => OpcionMenu(
        id: j['id'] as String,
        nombre: j['name'] as String? ?? '',
        cupo: (j['quota'] as num?)?.toInt() ?? 0,
        tomados: (j['reserved'] as num?)?.toInt() ?? 0,
      );
}

/// Estado de un ticket. 'servido' incluye lo marcado localmente sin señal.
enum EstadoTicket { vigente, servido, anulado }

EstadoTicket _estadoDesde(String? texto) => switch (texto) {
      'servido' => EstadoTicket.servido,
      'anulado' => EstadoTicket.anulado,
      _ => EstadoTicket.vigente,
    };

class Ticket {
  Ticket({
    required this.id,
    required this.codigo,
    required this.token,
    required this.persona,
    required this.area,
    required this.empresa,
    required this.acreditada,
    required this.opcion,
    required this.estado,
    required this.consumidoUtc,
    required this.comentario,
    this.anuladoUtc,
    this.paraLlevar = false,
  });

  final String id;
  final String codigo;
  final String token;
  final String persona;
  final String? area;
  final String? empresa;

  /// Viene de una empresa acreditada: llega con QR y no aparece en la lista del enlace general.
  final bool acreditada;

  final String opcion;
  EstadoTicket estado;
  DateTime? consumidoUtc;
  final String? comentario;

  /// Cuándo se anuló, si se anuló. El mesón necesita la hora para responderle a quien dice
  /// que no anuló nada.
  final DateTime? anuladoUtc;

  /// Se lo lleva: va en envase y no ocupa mesa. Hay que saberlo ANTES de servir en loza.
  final bool paraLlevar;

  /// Código en el formato en que se lee y se dicta: dos grupos de tres.
  String get codigoLegible =>
      codigo.length == 6 ? '${codigo.substring(0, 3)}-${codigo.substring(3)}' : codigo;

  factory Ticket.desdeJson(Map<String, dynamic> j) => Ticket(
        id: j['id'] as String,
        codigo: j['code'] as String? ?? '',
        token: j['token'] as String? ?? '',
        persona: j['personName'] as String? ?? '',
        area: j['area'] as String?,
        empresa: j['clientName'] as String?,
        acreditada: j['selfManaged'] as bool? ?? false,
        opcion: j['optionName'] as String? ?? '',
        estado: _estadoDesde(j['state'] as String?),
        consumidoUtc: j['consumedUtc'] == null
            ? null
            : DateTime.tryParse(j['consumedUtc'] as String)?.toUtc(),
        comentario: j['comment'] as String?,
        anuladoUtc: j['cancelledUtc'] == null
            ? null
            : DateTime.tryParse(j['cancelledUtc'] as String)?.toUtc(),
        paraLlevar: j['paraLlevar'] as bool? ?? false,
      );

  Map<String, dynamic> aJson() => {
        'id': id,
        'code': codigo,
        'token': token,
        'personName': persona,
        'area': area,
        'clientName': empresa,
        'selfManaged': acreditada,
        'optionName': opcion,
        'state': estado.name,
        'consumedUtc': consumidoUtc?.toIso8601String(),
        'comment': comentario,
        'cancelledUtc': anuladoUtc?.toIso8601String(),
        'paraLlevar': paraLlevar,
      };
}

class DiaDeTrabajo {
  DiaDeTrabajo({
    required this.fecha,
    required this.unidad,
    required this.estado,
    required this.nota,
    required this.opciones,
    required this.tickets,
    required this.bajadoUtc,
  });

  final String fecha;
  final String unidad;
  final String estado;
  final String? nota;
  final List<OpcionMenu> opciones;
  final List<Ticket> tickets;

  /// Cuándo se bajó esta copia: la app avisa si está vieja.
  final DateTime bajadoUtc;

  int get emitidos => tickets.where((t) => t.estado != EstadoTicket.anulado).length;
  int get servidos => tickets.where((t) => t.estado == EstadoTicket.servido).length;
  int get porServir => emitidos - servidos;

  factory DiaDeTrabajo.desdeJson(Map<String, dynamic> j) => DiaDeTrabajo(
        fecha: j['date'] as String? ?? '',
        unidad: j['unitName'] as String? ?? '',
        estado: j['status'] as String? ?? '',
        nota: j['notes'] as String?,
        opciones: ((j['options'] as List?) ?? [])
            .map((o) => OpcionMenu.desdeJson(o as Map<String, dynamic>))
            .toList(),
        tickets: ((j['tickets'] as List?) ?? [])
            .map((t) => Ticket.desdeJson(t as Map<String, dynamic>))
            .toList(),
        bajadoUtc: DateTime.now().toUtc(),
      );

  Map<String, dynamic> aJson() => {
        'date': fecha,
        'unitName': unidad,
        'status': estado,
        'notes': nota,
        'options': opciones
            .map((o) => {'id': o.id, 'name': o.nombre, 'quota': o.cupo, 'reserved': o.tomados})
            .toList(),
        'tickets': tickets.map((t) => t.aJson()).toList(),
        'cachedAt': bajadoUtc.toIso8601String(),
      };
}

/// Marca hecha en el mesón que todavía no llega al servidor.
class MarcaPendiente {
  const MarcaPendiente({required this.ticket, required this.operador, required this.cuandoUtc});

  final String ticket;
  final String operador;
  final DateTime cuandoUtc;

  Map<String, dynamic> aJson() => {
        'ticket': ticket,
        'operator': operador,
        'atUtc': cuandoUtc.toIso8601String(),
      };

  factory MarcaPendiente.desdeJson(Map<String, dynamic> j) => MarcaPendiente(
        ticket: j['ticket'] as String,
        operador: j['operator'] as String? ?? '',
        cuandoUtc: DateTime.parse(j['atUtc'] as String).toUtc(),
      );
}

/// Lo que el mesón necesita ver después de marcar.
///
/// Un vale no es una inscripción: no tiene plato ni aparece en la lista del día, así que el
/// servidor manda aparte el nombre de quien lo presentó y la plata. Por eso esto no puede ser
/// solo un [Ticket].
class RespuestaMarca {
  const RespuestaMarca(this.resultado, {this.ticket, this.persona, this.monto, this.valor});

  final ResultadoMarca resultado;
  final Ticket? ticket;

  /// De quién es el ticket, cuando no hay inscripción de dónde sacar el nombre.
  final String? persona;

  /// Lo efectivamente cobrado.
  final num? monto;

  /// Lo que valía el ticket. Si la compra fue mayor, la diferencia se paga en efectivo.
  final num? valor;

  /// Nombre a mostrar, venga de donde venga.
  String? get nombre => persona?.isNotEmpty == true ? persona : ticket?.persona;

  factory RespuestaMarca.desdeJson(
          Map<String, dynamic> j, ResultadoMarca resultado, Ticket? ticket) =>
      RespuestaMarca(
        resultado,
        ticket: ticket,
        persona: j['persona'] as String?,
        monto: j['monto'] as num?,
        valor: j['valor'] as num?,
      );
}

/// Resultado de marcar un ticket, ya interpretado para mostrarlo en pantalla.
enum ResultadoMarca {
  ok,
  yaConsumido,
  anulado,
  noExiste,
  otroDia,
  /// Su empresa lo desactivó. El ticket es válido, pero no se le sirve: casi siempre es
  /// alguien que ya no trabaja ahí.
  desactivado,
  /// Lo presentado era un vale acumulado y quedó cobrado.
  valeCobrado,
  /// El vale existe pero ya se había gastado.
  valeYaUsado,
  /// El ticket está comprometido con el almuerzo de hoy: se sirve en la fila, no se cobra.
  valeReservado,
  /// Se anotó pero su empresa todavía no le entrega el ticket.
  sinTicket,
  /// El ticket de esa empresa vale un almuerzo y nada más: en la caja no se cobra.
  soloParaAlmuerzo,
  /// El ticket venció sin alcanzar a usarse.
  vencido,
  /// Sin señal y el ticket no está en la copia del día: puede ser falso, de otro casino,
  /// o de alguien que se anotó después de la última descarga. No es un problema de red.
  fueraDeLaCopia,
  sinConexion,
}
