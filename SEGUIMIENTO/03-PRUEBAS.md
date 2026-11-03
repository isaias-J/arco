# Arco — Matriz de criterios de aceptación (T01–T76)

Estado: `core` verificado por `swift test` (ArcoCore) · `build` compila/renderiza en simulador ·
`ui` implementado en UI (pendiente de prueba interactiva) · `dev` requiere iPhone real · `pend`.

Resumen de verificación automática: **43 tests verdes** en ArcoCore (`swift test`).
Build de app: **BUILD SUCCEEDED** (simulador iPhone 17, iOS 27.2); arranca y renderiza.

| ID | Escenario (resumen) | Estado | Evidencia |
|----|---------------------|--------|-----------|
| T01 | Rutina precargada: 0 series hasta confirmar | core/ui | lógica en WorkoutRepository; cubierto por reglas de dominio |
| T02 | Confirmar fila válida: 1 serie, idempotente | core | idempotencia por setID en confirmSet |
| T03 | Cerrar tras guardar y reabrir: persiste | ui | activeSession() + SwiftData; probar interactivo |
| T04 | Fallo escritura: borrador, sin guardado falso | core/ui | validación lanza RepositoryError antes de guardar |
| T05 | Editar/eliminar serie pasada recalcula | core/ui | récords/conteos se recomputan desde registros |
| T06 | Cambiar plantilla: histórico conserva valores | ui | sesión guarda su selección; plantillas aparte |
| T07 | Calentamiento excluido de conteo/asistencia | core | SetRecord.isEligibleForWorkCount (test) |
| T08 | RIR vacío: serie válida | core | test de validación |
| T09 | D=2, I=4, F=4 | core | MuscleCounterTests (test) |
| T10 | Papel único por músculo | core | test |
| T11 | Dos regiones de hombro: unión/máximo | core | test |
| T12 | 3 pares unilaterales por lado | core | test |
| T13 | Solo un lado | core | test |
| T14 | Pulldown brazos ext. no suma bíceps | core | test |
| T15 | Prensa sentada no suma isquios | core | test |
| T16 | Agarre isométrico no antebrazo directo | core | test |
| T17 | Atribución desconocida pendiente | core | test |
| T18 | Cambiar versión de atribución | core/ui | versión guardada por serie |
| T19 | Sugerencia explica datos | core | SuggestionTests (test) |
| T20 | Catálogo sin apto: informa | core | test |
| T21 | Rechaza sugerencia sin penalización | core/ui | sugerencias no editan la sesión |
| T22 | Sin historial: no diagnostica | core | test |
| T23 | 100 lb → 45,359237 kg exacto | core | UnitsTests (test) |
| T24 | Mancuernas por unidad | core | convención perDumbbell (test) |
| T25 | Máquinas distintas separadas | core/ui | variante/alias por sesión |
| T26 | Asistencia no es más fuerza | core | RecordsTests (test) |
| T27 | 40×8 → 40×10 progreso reps | core | test |
| T28 | Más carga/menos reps: tradeoff | core | test |
| T29 | Borrar serie récord recalcula | core | test |
| T30 | Solo 1 serie al techo: no sube | core | test |
| T31 | % sin división inválida | core | ChartTests (test) |
| T32 | Fecha sin datos ≠ cero | core | test |
| T33 | Semana en curso parcial | core | test |
| T34 | 1ª serie crea asistencia auto | core | lógica repo + AttendanceEngine (test) |
| T35 | 2 sesiones + manual = 1 día | core | AttendanceWeightTests (test) |
| T36 | Sesión parcial conserva estado | core | test |
| T37 | Borrar última serie revisa auto | core/ui | reconcileAutomaticAttendance |
| T38 | Descanso no rompe racha | core/ui | plantillas con isRestDay |
| T39 | Cambiar plan no altera histórico | core | AdherenceMetrics (test) |
| T40 | Notificaciones denegadas: app funciona | ui | NotificationSettingsView muestra estado real |
| T41 | Asistencia antes de hora cancela aviso | ui | cancelAttendanceReview por fecha |
| T42 | Aviso respondido al día siguiente | ui/dev | userInfo con fecha; probar en iPhone |
| T43 | Posponer sin duplicar | ui/dev | snoozeAttendanceReview |
| T44 | Sin avisos contradictorios | ui/dev | reconcilePendingWindow |
| T45 | Bisiesto/año/semana/zona | core/ui | Calendar + AnnualCalendarView |
| T46 | Cruza medianoche conserva fecha | core/ui | trainingDate + zona de origen |
| T47 | Cámara denegada: resto usable | ui/dev | CameraCaptureView estado denegado |
| T48 | Foto privada, no fototeca | ui/dev | VaultCrypto; probar en iPhone |
| T49 | 3 poses, 1 pesaje | ui | bodyWeightID vinculado |
| T50 | Foto sin peso y peso sin foto | core/ui | flujos independientes |
| T51 | Peso sugerido antiguo no crea medición | ui | AddWeight explícito |
| T52 | Peso actual por fecha de medición | core | test |
| T53 | Último estimado etiquetado; tendencia medidos | core | test |
| T54 | Borrar último pesaje vuelve al anterior | core/ui | currentWeight por fecha |
| T55 | IMC 24,2 mostrado | core | BMITests (test) |
| T56 | Clasifica sin redondear | core | test |
| T57 | Edad 19 → referencia 18+ | core/ui | banda NHS/NICE etiquetada |
| T58 | Cambio de altura conserva vigente | core/ui | HeightEntry histórico |
| T59 | Medidas izq/der y protocolos no se mezclan | ui | BodyMeasurementsView separa series |
| T60 | PIN incorrecto: limitación coherente | ui/dev | PINAuth persistente; probar en iPhone |
| T61 | Face ID cancelado: bloqueada | ui/dev | BiometricAuth; probar en iPhone |
| T62 | Misma autenticación en todas las rutas | ui | VaultLock único punto |
| T63 | Selector de apps no expone foto | ui/dev | VaultPrivacyScreen; probar en iPhone |
| T64 | Olvidé PIN requiere auth del sistema | ui/dev | resetPINAfterOwnerAuthentication |
| T65 | Fotos cifradas; sin claves en export/logs | core/ui | VaultCrypto + export sin secretos |
| T66 | Atributos backup/protección reaplicados | ui/dev | reapplyProtectionAttributes |
| T67 | Borrar foto elimina derivados | ui | deleteEncryptedFile |
| T68 | Secuencia: orden, filtro, memoria | ui | VaultImageLoader acotado |
| T69 | CSV seguro con tildes/fórmulas | core | CSVTests (test) |
| T70 | Archivo cifrado: mala contraseña no modifica | core | BackupArchiveTests (test) |
| T71 | Restauración limpia con nuevas claves | core/ui | DataImport transaccional |
| T72 | Reimportación no duplica | core/ui | DataImport omite IDs existentes |
| T73 | Migración conserva datos | ui/dev | SwiftData; probar con esquema real |
| T74 | Claro/oscuro/texto grande/VoiceOver | ui/dev | tokens + labels; probar en iPhone |
| T75 | Sin conexión: todo funciona | ui | 100% local, sin red |
| T76 | Primera apertura sin datos demo | core/ui | seed solo catálogo/plantillas, no entrenos |

## Comandos de verificación
```
cd ArcoCore && swift test     # 43 tests, sin simulador
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project Arco.xcodeproj -scheme Arco \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```
