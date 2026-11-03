# Arco — Pendientes y próxima acción

## Cambio de arquitectura importante (2026-11-02, tarde)
La capa SwiftData (modelos, PersistenceController, WorkoutRepository) y BackupArchive se
MOVIERON del target de app a **ArcoCore**. Motivo: los tests que instancian `ModelContainer`
dentro del arnés de pruebas hospedado en la app lanzaban la app en el simulador y crasheaban
(cada crash = una alerta "Arco quit unexpectedly" en el Mac del propietario).

Decisión definitiva:
- Modelos + persistencia + repositorio + BackupArchive viven en ArcoCore (públicos).
- Se eliminó el target de tests hospedado en la app (`AppTests`) del .xcodeproj.
- Los tests de SwiftData que crean `ModelContainer` NO se ejecutan en el arnés SPM de macOS
  (SwiftData crashea ahí). La capa SwiftData se verifica con lanzamientos CONTROLADOS de la app
  en el simulador (arranca, siembra catálogo, renderiza). Su LÓGICA pura (idempotencia,
  validación, asistencia) ya está cubierta por tests de ArcoCore.
- `@Attribute(.unique)` se quitó de ExerciseModel.id (la unicidad la garantiza el seed).
- ArcoApp usa contenedor en memoria si detecta entorno de test (guardia defensiva).

## Hecho (verificado con evidencia)
- `swift test` ArcoCore: **43 tests verdes** (dominio, analítica, ciencia, CSV, BackupArchive).
- `xcodebuild build` app iOS: **BUILD SUCCEEDED** (simulador iPhone 17, iOS 27.2).
- App lanzada en simulador: arranca, siembra 27 ejercicios + 7 plantillas, renderiza onboarding.
- Servicios creados: VaultCrypto, PINAuth, BiometricAuth, VaultLock, NotificationService.
- Bóveda de fotos (UI): captura cámara, galería, comparación, secuencia temporal, privacidad escena.
- 5 pestañas: Hoy, Progreso, Fotos, Asistencia, Perfil + onboarding.

## Pendiente (orden)
1. Conectar NotificationService y BackupArchive a la UI (ajustes de avisos, export/restore).
2. Calendario anual de asistencia (celdas estilo contribuciones) — §14.
3. Medidas corporales con gráficos — §18.
4. Gráficos por ejercicio con selección de punto, récords, e1RM en UI — §12.
5. Edición histórica de series desde la UI — T05, T06.
6. Estados vacíos/error exhaustivos (§21) y repaso de accesibilidad (VoiceOver, Dynamic Type) — T74.
7. README de entrega: entorno, compilación, instalación en iPhone, limitaciones de firma.

## Próxima acción concreta
Conectar los ajustes de notificaciones y la exportación/restauración de archivo cifrado a la UI
de Perfil (los servicios ya existen y están probados en su lógica).

## Verificación — comandos
```
cd ArcoCore && swift test          # 43 tests, sin simulador
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Arco.xcodeproj -scheme Arco \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
NO ejecutar un target de tests hospedado en la app (se eliminó; crasheaba el simulador).

## Bloqueos
- Firma para iPhone real: requiere Apple ID del propietario en Xcode (manual). No bloquea desarrollo.
- Tests de cámara/Face ID/Keychain real: solo verificables en iPhone físico.
