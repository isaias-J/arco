> Estado vigente: ver `04-PENDIENTES.md`, `03-PRUEBAS.md` y `06-REVISION-CORRECCIONES.md`.
> Lo que sigue es el registro inicial del entorno y de la arquitectura.

# Arco — Estado del proyecto

Última actualización: 2026-11-02

## Entorno verificado
- macOS (darwin), Apple Silicon.
- Xcode **27.2** (Build 27B52) en `/Applications/Xcode.app`.
- **IMPORTANTE**: `xcode-select -p` apunta a `/Library/Developer/CommandLineTools`. Cambiarlo requiere `sudo`.
  Por eso todos los comandos de build usan el prefijo:
  `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
- SDK iOS **27.2** (`iphoneos27.2`, `iphonesimulator27.2`).
- Swift **6.4.2**.
- Simuladores disponibles: iPhone 17, iPhone 17e, iPhone 18 Pro, iPhone 18 Pro Max, iPhone Air, iPhone Duo (todos iOS 27.2).
- No hay `xcodegen`, `tuist` ni gem `xcodeproj`. Ruby del sistema = 2.6.

## Estrategia de arquitectura (decisión)
El proyecto se divide en dos piezas que viven en el mismo repo:

1. **ArcoCore** — Swift Package multiplataforma (compila en macOS sin simulador).
   Contiene toda la lógica pura y verificable por `swift test`:
   - `Domain`     → unidades, reglas de series, sesiones, asistencia, progresión, IMC.
   - `Science`    → catálogo, nodos musculares, reglas de atribución versionadas, fuentes.
   - `Analytics`  → conteos musculares, récords, e1RM, agregaciones de gráficos.
   - `Persistence`→ contratos de repositorio + modelos SwiftData (tipos compartidos).
   Ventaja: los 76 criterios T01–T76 que son reglas de negocio se prueban aquí, rápido,
   sin depender del simulador.

2. **Arco (app iOS)** — target de app SwiftUI en `Arco.xcodeproj`, que **depende de ArcoCore**.
   Contiene presentación (vistas SwiftUI), servicios que tocan el sistema
   (cámara, notificaciones, LocalAuthentication, Keychain, cifrado de ficheros) y el
   contenedor SwiftData real. Se compila con `xcodebuild` contra el simulador.

El `.xcodeproj` usa **PBXFileSystemSynchronizedRootGroup** (Xcode 16+) para no listar cada
archivo en el pbxproj: basta con añadir ficheros a las carpetas sincronizadas.

### Por qué SwiftData y no Core Data
La spec admite ambos. SwiftData (iOS 17+) reduce boilerplate, es el camino moderno de Apple,
e integra con `@Observable`. Objetivo de despliegue iOS 18 (hay SDK 27 y el iPhone 14 del
propietario soporta iOS 18). Los tipos derivados se recalculan desde registros originales;
la caché nunca es única copia (regla de la spec §4).

## Decisión sobre Swift Concurrency
- `@MainActor` solo para estado de UI (`@Observable` view models y servicios UI-bound).
- Lógica de dominio pura: value types `Sendable`, sin isolation.
- Cifrado/ficheros/cámara: trabajo fuera del main actor con hop de vuelta para UI.
- Modo de lenguaje Swift 6 con data-race safety.

## Objetivo de despliegue
- iOS 18.0 mínimo (iPhone 14 lo soporta; APIs modernas gated con `#available` si hace falta).
- Idioma base: español. Localización preparada.

Ver `01-REQUISITOS.md`, `02-DECISIONES.md`, `03-PRUEBAS.md`, `04-PENDIENTES.md`.
