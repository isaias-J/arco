# Arco — Requisitos y estado por etapa (spec §23)

## Etapa A — Base verificable ✅ (compilada + probada)
- [x] Inspección de entorno y repositorio.
- [x] Proyecto nativo (`Arco.xcodeproj`) que compila en simulador iOS 27.2 y arranca.
- [x] Entidades (SwiftData `@Model`): perfil, ajustes, ejercicio, sesión, serie, peso, altura,
      medida, foto, asistencia, recordatorio, plantilla.
- [x] Persistencia con seed idempotente del catálogo (27 ejercicios) y plantillas (5 días + 2 descansos).
- [x] Unidades exactas (kg/lb, cm/in) sin deriva — T23, T24 verificados.
- [x] Navegación de 5 destinos (Hoy, Progreso, Fotos, Asistencia, Perfil) + onboarding.

## Etapa B — Entrenamiento completo 🟡 (núcleo probado; UI base funcional)
- [x] Registro rápido por serie con persistencia inmediata (SessionView).
- [x] Confirmación idempotente por setID (WorkoutRepository) — T02.
- [x] Recuperación de sesión activa (activeSession) — T03 (lógica lista; falta prueba UI).
- [x] Asistencia automática al confirmar 1ª serie de trabajo — T34 (lógica + repo).
- [x] Validación de series (dominio) — T07, T08, T10.
- [ ] Edición histórica desde UI con recálculo visible — T05, T06 (lógica lista en ArcoCore).
- [ ] Unilateralidad en UI (filas por lado) — T12, T13 (motor probado).

## Etapa C — Cálculos y sugerencias ✅ núcleo / 🟡 UI
- [x] Conteos D/I/F/U versionados — T09, T11, T14-T17.
- [x] Récords y doble progresión — T26-T30.
- [x] e1RM Epley filtrado — §12.
- [x] Motor de sugerencias explicable — T19-T22.
- [x] Gráfico de series por grupo (Progreso) — parcial, honesto.
- [ ] Gráficos por ejercicio con selección de punto — T31-T33 (lógica lista).

## Etapa D — Perfil, calendario y avisos 🟡
- [x] Pesajes, IMC (NHS/NICE 18+), peso actual por fecha de medición — T52-T57.
- [x] Asistencia manual/automática y resumen — T34-T36.
- [x] NotificationService con reconciliación de ventana — T40-T44 (lógica; falta prueba).
- [ ] Calendario anual de celdas — §14.
- [ ] Medidas corporales con gráficos — §18.

## Etapa E — Bóveda completa 🟡
- [x] VaultCrypto (AES-GCM + Keychain + protección de archivo + exclusión backup).
- [x] PINAuth (verificador con sal, limitación de intentos persistente) — T60, T64.
- [x] BiometricAuth (Face ID) — T61.
- [x] VaultLock orquestador + pantalla de bloqueo/PIN.
- [ ] Captura de cámara (AVFoundation) — T47, T48.
- [ ] Comparación y secuencia temporal — §16.
- [ ] Archivo cifrado export/restore conectado a datos — T70-T73 (BackupArchive listo).

## Etapa F — Diseño y validación integral 🟡
- [x] Tokens claro/oscuro (azules), tarjetas con profundidad.
- [x] Icono vectorial original (curva ascendente) renderizado a 1024.
- [ ] Accesibilidad completa (VoiceOver, Dynamic Type) — T74.
- [ ] Estados vacíos y de error exhaustivos — §21.

## Verificación actual
- `swift test` en ArcoCore: 39 tests verdes (reglas de negocio).
- `xcodebuild build` app iOS: **BUILD SUCCEEDED** (simulador iPhone 17, iOS 27.2).
- App instalada y lanzada en simulador sin crash; onboarding renderiza en español.
