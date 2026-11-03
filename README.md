# Arco

App nativa de iPhone para registrar entrenamiento de hipertrofia, observar el progreso y
mantener la constancia. Privada y local: tus datos y fotos se guardan solo en tu dispositivo.

El nombre "Arco" es provisional y configurable dentro de la app.

---

## 1. Entorno real usado

- **Xcode 27.2** (build 27B52).
- **SDK iOS 27.2**; objetivo de despliegue **iOS 18.0** (compatible con iPhone 14).
- **Swift 6.4.2**, modo de lenguaje Swift 6 con seguridad de datos estricta.
- Simuladores usados para verificación: iPhone 17 (iOS 27.2).

> Nota: en esta máquina `xcode-select` apunta a las Command Line Tools. Para compilar por
> línea de comandos se antepone `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
> Abriendo el proyecto en Xcode.app directamente NO hace falta.

## 2. Estructura del proyecto

```
arco/
├── Arco.xcodeproj           ← proyecto de app (abrir este en Xcode)
├── App/Arco/                ← target de app (SwiftUI, servicios del sistema, vistas)
│   ├── ArcoApp.swift        ← punto de entrada; crea el contenedor SwiftData
│   ├── AppState.swift       ← estado global (@Observable @MainActor)
│   ├── DesignSystem/        ← tokens de color/espaciado, tarjetas
│   ├── Services/            ← cámara, notificaciones, cifrado, PIN, Face ID, bloqueo bóveda
│   ├── Views/               ← Hoy, Progreso, Fotos, Asistencia, Perfil, onboarding
│   ├── Assets.xcassets/     ← colores, icono de app
│   └── Info.plist           ← permisos (cámara, Face ID)
├── ArcoCore/                ← Swift Package: lógica pura + persistencia (probable por CLI)
│   └── Sources/ArcoCore/
│       ├── Domain/          ← unidades, series, IMC, peso, asistencia, parser decimal
│       ├── Science/         ← catálogo (27 ejercicios), músculos, atribuciones, sugerencias
│       ├── Analytics/       ← conteo muscular, récords, e1RM, CSV, gráficos
│       └── Persistence/     ← modelos SwiftData, repositorio, archivo de respaldo
│   └── Tests/ArcoCoreTests/ ← 43 pruebas de reglas de negocio
├── SEGUIMIENTO/             ← documentación de requisitos, decisiones, pruebas, pendientes
└── ARCO_PAQUETE_PARA_CLAUDE/← especificación original (prompt maestro) y referencias
```

**Decisión de arquitectura:** la lógica de negocio y la capa de persistencia (modelos
SwiftData, repositorio) viven en el paquete `ArcoCore` para poder probarlas con `swift test`
sin lanzar la app. El target de app contiene la presentación SwiftUI y los servicios que tocan
el sistema (cámara, notificaciones, LocalAuthentication, Keychain, cifrado de ficheros).

## 3. Cómo compilar y probar

### Pruebas de reglas de negocio (rápidas, sin simulador)
```bash
cd ArcoCore && swift test
```
Resultado esperado: **43 tests en 9 suites, todos en verde**. Cubren unidades y conversión
exacta, conteo muscular D/I/F/U, IMC, récords, doble progresión, e1RM, sugerencias, CSV y el
archivo de respaldo cifrado.

### Compilar la app para el simulador
```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Arco.xcodeproj -scheme Arco \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
Resultado esperado: **BUILD SUCCEEDED**.

### Ejecutar en el simulador
Abre `Arco.xcodeproj` en Xcode, elige un simulador iPhone y pulsa Run (⌘R). O desde la línea
de comandos instala el `.app` generado con `xcrun simctl install` y `launch`.

> Importante: NO hay un target de pruebas hospedado en la app. Las pruebas de SwiftData se
> ejecutan como lógica en `ArcoCore` (`swift test`), no lanzando la app.

## 4. Instalar en tu iPhone (firma)

La instalación en un iPhone real requiere **tu** cuenta de Apple (firma de código). No se puede
automatizar desde aquí sin tus credenciales. Pasos:

1. Abre `Arco.xcodeproj` en Xcode.
2. Selecciona el target **Arco** → pestaña **Signing & Capabilities**.
3. En **Team**, elige tu Apple ID (añádelo con Xcode → Settings → Accounts si no aparece).
4. Xcode generará un perfil de aprovisionamiento personal automático. Puede que debas cambiar el
   **Bundle Identifier** (`com.arco.app`) por uno único tuyo si hay conflicto.
5. Conecta tu iPhone 14, selecciónalo como destino y pulsa Run.
6. La primera vez, en el iPhone: Ajustes → General → VPN y gestión de dispositivos → confía en
   tu certificado de desarrollador.

Con una cuenta gratuita, la app caduca a los 7 días y debe reinstalarse; con el Apple Developer
Program dura un año.

## 5. Política de almacenamiento y recuperación

- **Todo es local.** Sin iCloud, CloudKit, servidores, cuentas ni analítica externa. La base de
  datos SwiftData se marca excluida de la copia automática de iCloud.
- **Fotos privadas (bóveda):** se guardan **cifradas** (AES-GCM, clave de 256 bits en Keychain
  con protección "solo este dispositivo, desbloqueado") en el contenedor privado de la app,
  fuera de Apple Fotos. Nunca se escriben en el álbum Ocultos ni en la fototeca.
- **PIN de 4 dígitos + Face ID opcional** protegen el acceso a las fotos. El PIN se guarda como
  verificador derivado con sal (no en texto plano); la clave de cifrado de las fotos NO se
  deriva del PIN.
- **Copia de seguridad:** puedes exportar un **archivo cifrado** con contraseña propia (separada
  del PIN) desde Perfil → Copia de seguridad. La restauración valida contraseña e integridad
  **antes** de tocar tus datos y no duplica registros existentes. También puedes exportar un
  **CSV** de tus series.
- Una copia local no sustituye a un respaldo si pierdes el teléfono: exporta el archivo cifrado
  y guárdalo donde elijas.

## 6. Qué está verificado y qué queda pendiente de tu iPhone

Ver `SEGUIMIENTO/03-PRUEBAS.md` para el detalle por criterio (T01–T76).

**Verificado por pruebas automáticas (`swift test`, 43 tests):** reglas de unidades y conversión
(T23, T24), conteo muscular y atribuciones (T09–T17), récords/progresión/e1RM (T26–T30), IMC
(T55–T57), peso y asistencia (T34–T39, T52, T53), CSV seguro (T69) y archivo cifrado (T70).

**Verificado compilando y ejecutando en simulador:** la app compila sin errores ni warnings,
arranca, siembra el catálogo (27 ejercicios) y las plantillas semanales, y renderiza el
onboarding y la navegación de 5 pestañas.

**Pendiente de comprobar en tu iPhone 14 real (no verificable en simulador):**
- Captura de cámara real y que la foto queda cifrada fuera de Apple Fotos (T47, T48).
- Face ID real y que la bóveda permanece bloqueada si se cancela (T61, T62).
- Que al pasar a segundo plano el selector de apps no expone la foto (T63).
- Entrega real de notificaciones locales y acciones de la revisión de asistencia (T40–T44).
- Rendimiento de la galería con cientos de fotos y varios años de datos.

No se declara superado ningún criterio marcado como pendiente: requiere tu dispositivo.

## 7. Decisiones de producto incorporadas (de la especificación)

- Registro rápido por serie con confirmación en un toque y persistencia inmediata.
- **Sin temporizador de descanso** (el temporizador de la cámara sí existe).
- Catálogo flexible; las plantillas definen grupos del día, no ejercicios fijos.
- Sugerencias de énfasis muscular **explicables** y deterministas, basadas en tu registro.
- RIR opcional; conteo directo/indirecto/fraccional con el modelo etiquetado como estimación.
- IMC con marco adulto NHS/NICE (18+), identificado y sin diagnóstico.
- Datos personales desconocidos (fecha de nacimiento, altura, peso, metas) se configuran en la
  app; no se inventan.

Las fuentes científicas y las reglas de atribución muscular están documentadas en
`SEGUIMIENTO/05-FUENTES.md`.
