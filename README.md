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
ArcoCore/Tests/         126 pruebas (lógica e integración con SwiftData real)
AppUITests/             19 recorridos de interfaz (XCUITest)
SEGUIMIENTO/            requisitos, decisiones, matriz de pruebas, pendientes, seguridad, etapas,
                        verificaciones para el iPhone (09), segunda y tercera revisión (10, 11)
scripts/preflight-publico.sh   revisión de seguridad antes de cada push
```

## 3. Compilar y probar
```bash
cd ArcoCore && swift test                         # 126 pruebas, sin simulador

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Arco.xcodeproj -scheme Arco \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# Recorridos de interfaz en un simulador aislado (borra los datos DE ESE simulador al empezar):
xcrun simctl create "Arco-QA" com.apple.CoreSimulator.SimDeviceType.iPhone-17 com.apple.CoreSimulator.SimRuntime.iOS-27-2
xcodebuild -project Arco.xcodeproj -scheme Arco -destination 'platform=iOS Simulator,name=Arco-QA' test
```
Los recorridos de interfaz arrancan la app con `-arco-uitest-reset`, que borra la base, el PIN y
la bóveda **del simulador donde se ejecutan**. No los ejecutes en un dispositivo con datos reales.
Ejecútalos con la firma habitual del simulador: con `CODE_SIGNING_ALLOWED=NO` el recorrido del PIN
falla (causa exacta no demostrada; ver `SEGUIMIENTO/10-SEGUNDA-REVISION.md`).

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
  de cambiar nada y vuelve a cifrar las fotos con la clave del nuevo dispositivo. Antes de
  restaurar muestra qué se añadirá, qué ya está, qué conflictos hay y qué se eliminaría. Opciones:
  **Combinar** (recomendado; ante un conflicto conserva este iPhone), **Combinar usando la copia en
  los conflictos** (ninguna de las dos elimina nada, tampoco borradores sin confirmar), o
  **Reemplazar con la copia** (segunda confirmación que enumera lo que se eliminará; nunca borra
  fotos ni ejercicios del catálogo, y nombra los ejercicios que conserva). Reglas
  completas en `SEGUIMIENTO/10-SEGUNDA-REVISION.md`. También puedes restaurar desde la primera
  pantalla de configuración.
- Si pierdes el iPhone sin una copia exportada, los datos y fotos no se pueden recuperar.

## 6. Qué está verificado
Detalle por criterio en `SEGUIMIENTO/03-PRUEBAS.md`.
- **Con datos simulados (126 pruebas):** conteo muscular y pares unilaterales, atribuciones
  (incluidas las personalizadas), récords, gráficas sin asistencia, peso e IMC, asistencia y
  descansos, días de la rutina, historial de versiones de la rutina en la adherencia y la racha,
  planificador de avisos (cancelación, aplazamiento, horarios por día, fechas límite), catálogo
  (renombrar, alias, archivar, incremento y barra), sustituir y reordenar en sesión, doble
  progresión, resumen semanal, fuentes, registro de series con fallo de guardado, persistencia en
  disco, migraciones v1→v2→v3, exclusión de copias de la base, y copia cifrada completa con fotos
  restaurada en una instalación limpia con otra clave, con contraseña incorrecta, archivo dañado
  y reimportación; restauración sobre datos existentes (catálogo, sesiones y series en ambos
  órdenes, conflictos, borrados, reemplazo, copias anteriores, fallo a mitad); curvas de series
  por músculo y de repeticiones.
- **En el simulador aislado (19 recorridos, una sola corrida):** primera apertura sin datos de demostración y fecha
  de inicio opcional; registrar una serie, cerrar la app y recuperarla; asistencia creada por la
  serie; "Hoy descansé"; validación de peso; PIN de la bóveda; copia honesta sobre las fotos; tema
  oscuro con texto grande; sugerencia de énfasis explicada y rechazable; renombrar y archivar un
  ejercicio conservando su historial; editar la rutina desde hoy; sustituir un ejercicio en la
  sesión; aviso de doble progresión sin cambiar pesos; resumen semanal y fuentes; series por músculo
  en el tiempo y repeticiones (también en oscuro con texto grande); guía de poses; exportar y
  restaurar con el selector de Archivos (contraseña incorrecta, previsión, reemplazo con
  confirmación, mensaje final).

## 7. Pendiente de comprobar en tu iPhone
Pasos exactos y resultado esperado en `SEGUIMIENTO/09-VERIFICACION-IPHONE.md`: cámara y permiso,
fotos fuera de Apple Fotos, varias poses con un pesaje, Face ID y "Olvidé mi PIN", selector de
apps, entrega real de avisos y sus botones, copia a Archivos y restauración tras reinstalar,
borrado de fotos, modo avión, VoiceOver y rendimiento con muchas fotos.

## 8. Limitaciones conocidas
- Las ilustraciones de poses son siluetas esquemáticas; las poses personalizadas usan un símbolo genérico.
- Combinar una copia anterior puede devolver un pesaje o un registro de asistencia que borraste después (no se guarda el borrado); "Reemplazar" deja exactamente la copia.
- Los avisos se programan para 4 semanas; sin abrir la app en ese tiempo, se detienen.
- Exportar con muchas fotos se hace en primer plano y puede tardar.
- Solo existe la atribución muscular v1.0; no hay pantalla para recalcular con otra versión.
- Los días anteriores al primer uso de Arco no cuentan para la asistencia ("Antes de usar Arco").
