# Arco

App nativa de iPhone para registrar entrenamiento de hipertrofia, observar el progreso y
mantener la constancia. Privada y local: los datos y las fotos se guardan solo en el dispositivo.

## 1. Entorno usado
- Xcode 27.2, SDK iOS 27.2, objetivo de despliegue iOS 18.0 (compatible con iPhone 14).
- Swift 6 (modo de lenguaje 6, seguridad de concurrencia estricta).
- En esta máquina `xcode-select` apunta a Command Line Tools: por línea de comandos se antepone
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Desde Xcode.app no hace falta.

## 2. Estructura
```
Arco.xcodeproj          proyecto (abrir este)
App/Arco/               app SwiftUI: vistas, servicios del sistema (cámara, avisos, Face ID, cifrado)
ArcoCore/               paquete Swift: dominio, ciencia, analítica, modelos SwiftData, repositorios,
                        copia cifrada portable, planificador de avisos
ArcoCore/Tests/         86 pruebas (lógica e integración con SwiftData real)
AppUITests/             7 recorridos de interfaz (XCUITest)
SEGUIMIENTO/            requisitos, decisiones, matriz de pruebas, pendientes, seguridad
scripts/preflight-publico.sh   revisión de seguridad antes de cada push
```

## 3. Compilar y probar
```bash
cd ArcoCore && swift test                         # 86 pruebas, sin simulador

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Arco.xcodeproj -scheme Arco \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Recorridos de interfaz en un simulador aislado (borra los datos DE ESE simulador al empezar):
xcrun simctl create "Arco-QA" com.apple.CoreSimulator.SimDeviceType.iPhone-17 com.apple.CoreSimulator.SimRuntime.iOS-27-2
xcodebuild -project Arco.xcodeproj -scheme Arco -destination 'platform=iOS Simulator,name=Arco-QA' test
```
Los recorridos de interfaz arrancan la app con `-arco-uitest-reset`, que borra la base, el PIN y
la bóveda **del simulador donde se ejecutan**. No los ejecutes en un dispositivo con datos reales.

## 4. Instalar en el iPhone
1. Abre `Arco.xcodeproj` en Xcode → target **Arco** → **Signing & Capabilities**.
2. En **Team** elige tu Apple ID (Xcode → Settings → Accounts si no aparece). Si hay conflicto,
   cambia el Bundle Identifier `com.arco.app` por uno propio.
3. Conecta el iPhone, selecciónalo como destino y pulsa Run.
4. En el iPhone: Ajustes → General → VPN y gestión de dispositivos → confía en tu certificado.
Con una cuenta gratuita la instalación caduca a los 7 días.

## 5. Almacenamiento, privacidad y copias
- Todo es local: sin iCloud, CloudKit, servidores ni analítica. La base SwiftData y sus archivos
  auxiliares se marcan excluidos de la copia automática en cada arranque (comprobado en pruebas
  sobre macOS; pendiente de comprobar en el iPhone).
- Fotos: cifradas con AES-GCM y una clave aleatoria en el Keychain de este dispositivo
  (`WhenUnlockedThisDeviceOnly`, no sincronizable), fuera de Apple Fotos. PIN de 4 dígitos y
  Face ID opcional. El PIN no es la clave de cifrado: restablecerlo no borra fotos.
- **Copia cifrada** (Perfil → Copia de seguridad): contraseña propia de 8+ caracteres. Incluye
  sesiones y series, ejercicios personalizados, rutina, perfil, ajustes, pesos, alturas, medidas,
  asistencia, descansos, recordatorios y metas; **las fotos solo si la bóveda está desbloqueada y
  marcas la opción** (la pantalla indica "Fotos: sí/no"). Restaurar valida todo el archivo antes
  de cambiar nada, no duplica lo existente y vuelve a cifrar las fotos con la clave del nuevo
  dispositivo. También puedes restaurar desde la primera pantalla de configuración.
- Si pierdes el iPhone sin una copia exportada, los datos y fotos no se pueden recuperar.

## 6. Qué está verificado
Detalle por criterio en `SEGUIMIENTO/03-PRUEBAS.md`.
- **Con datos simulados (86 pruebas):** conteo muscular y pares unilaterales, atribuciones,
  récords, gráficas sin asistencia, peso e IMC, asistencia y descansos, días de la rutina,
  planificador de avisos (cancelación, aplazamiento, horarios por día, fechas límite), registro
  de series con fallo de guardado, persistencia en disco, migración del esquema, exclusión de
  copias de la base, y copia cifrada completa con fotos restaurada en una instalación limpia
  con otra clave, con contraseña incorrecta, archivo dañado y reimportación.
- **En el simulador aislado (7 recorridos):** primera apertura sin datos de demostración;
  registrar una serie, cerrar la app y recuperarla; asistencia creada por la serie; "Hoy
  descansé" persistente; validación de peso; PIN de la bóveda; pantalla de copia honesta sobre
  las fotos; tema oscuro con texto grande.

## 7. Pendiente de comprobar en tu iPhone
Cámara y fotos guardadas en la bóveda; varias poses con un solo pesaje; Face ID (éxito, cancelar,
fallo); "Olvidé mi PIN" con el código del dispositivo; que el selector de apps no muestre fotos;
entrega real de avisos y sus botones "Sí fui", "Hoy descansé" y "Voy más tarde"; exportar la copia
a Archivos y restaurarla tras reinstalar; borrado de fotos; rendimiento con cientos de fotos;
VoiceOver; modo avión.

## 8. Limitaciones conocidas
- No se guardan versiones de la rutina: cambiarla altera el cumplimiento de las últimas 4 semanas.
- Las poses usan símbolos genéricos, no ilustraciones propias.
- Los avisos se programan para 4 semanas; sin abrir la app en ese tiempo, se detienen.
- Exportar con muchas fotos se hace en primer plano y puede tardar.
