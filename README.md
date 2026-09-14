# Makki · Fila

Lector de tickets del casino para el mesón. Escanea el QR del comensal, marca el consumo y
permite buscar a mano a quien se anotó por el enlace general y llegó sin QR.

## Por qué está hecho así

- **Se autoriza el equipo, no a la persona.** El teléfono o tablet del mesón se enrola una vez
  con un código que entrega el panel, y guarda un token propio. Lo usan varios turnos de Makki;
  pedir usuario y clave en cada almuerzo detiene la fila. Quien opera se identifica una vez al
  día para que quede registrado quién marcó, pero el permiso es del aparato. Si se pierde, se
  revoca desde el panel y deja de servir al instante.
- **Funciona sin señal.** Al abrir baja el día completo —minuta, cupos y tickets— y marca contra
  esa copia. Lo que no alcanza a llegar al servidor queda en una cola con **la hora real** en que
  ocurrió, no la de la sincronización. El wifi del casino no puede detener la fila.
- **La respuesta se ve de lejos.** El veredicto ocupa media pantalla en verde, naranjo o rojo, y
  vuelve solo a la cámara: en el mesón nadie tiene una mano libre para tocar «siguiente».
- **Leer dos veces el mismo QR no es un error.** Responde «ya fue servido» con la hora original.

## Estructura

    lib/main.dart              arranque y tema
    lib/src/app_state.dart     estado: copia local, cola offline y decisiones de marcado
    lib/src/api/               cliente HTTP y modelos
    lib/src/data/              lo que se guarda en el equipo
    lib/src/screens/           enrolar · inicio · escáner · lista

El repositorio versiona solo `lib/` y `pubspec.yaml`. Las carpetas de plataforma las genera el
CI con `flutter create`, igual que en la app de AOLAB.

## Compilar

El APK se arma en GitHub Actions y se publica como Release. Para trabajar en local hace falta
Flutter 3.44.8 y correr primero:

    flutter create --org cl.makki --project-name makki_fila --platforms=android .
    flutter pub get
    flutter run
