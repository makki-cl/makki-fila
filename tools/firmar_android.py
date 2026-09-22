"""Deja el proyecto Android generado listo para firmar con la clave de Makki.

La carpeta android/ no está versionada: la crea `flutter create` en cada compilación, y viene
apuntando a la clave de depuración. Esa clave el runner la inventa de cero cada vez, así que
cada APK salía firmado distinto y Android rechazaba la actualización con failureConflict: la
app quedaba instalable, pero imposible de actualizar.

Este archivo inyecta la configuración de firma en el build.gradle.kts recién generado.
"""

import pathlib
import re
import sys

FIRMA = '''    signingConfigs {
        create("release") {
            val props = java.util.Properties()
            rootProject.file("key.properties").inputStream().use { props.load(it) }
            storeFile = file(props.getProperty("storeFile"))
            storePassword = props.getProperty("storePassword")
            keyAlias = props.getProperty("keyAlias")
            keyPassword = props.getProperty("keyPassword")
        }
    }

'''

gradle = pathlib.Path('android/app/build.gradle.kts')
if not gradle.exists():
    sys.exit('No existe android/app/build.gradle.kts: ¿corrió flutter create?')

s = gradle.read_text()
if 'signingConfigs' in s and 'key.properties' in s:
    print('Ya estaba configurado.')
    sys.exit(0)

if '    buildTypes {' not in s:
    sys.exit('No encontré el bloque buildTypes: cambió la plantilla de Flutter.')

s = s.replace('    buildTypes {', FIRMA + '    buildTypes {', 1)
s, n = re.subn(r'signingConfig\s*=\s*signingConfigs\.getByName\("debug"\)',
               'signingConfig = signingConfigs.getByName("release")', s)
if n == 0:
    sys.exit('No encontré la firma de depuración que había que reemplazar.')

gradle.write_text(s)
print(f'Firma de release configurada ({n} referencia reemplazada).')
