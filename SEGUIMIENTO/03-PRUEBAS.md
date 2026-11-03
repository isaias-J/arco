# Arco — Matriz de requisitos y criterios de aceptación

Actualizada: 2026-11-02, al cierre de la revisión integral.

**Estados:** *no implementado* · *implementado sin probar* · *probado con datos simulados*
(pruebas automáticas de ArcoCore con SwiftData real en memoria o en disco temporal) ·
*probado en simulador* (recorrido XCUITest en el simulador aislado "Arco-QA") · *requiere iPhone*
(no verificable sin el dispositivo físico) · *parcial* (lo que falta se indica).
Ningún criterio está **probado en iPhone real** todavía.

**Evidencia ejecutada**
- `cd ArcoCore && swift test` → 86 pruebas, 14 suites, en verde (repetido 3 veces sin fallos).
- `xcodebuild -scheme Arco -destination 'id=<Arco-QA>' test` → 7 recorridos de interfaz en verde.
- Archivos: `ArcoCore/Tests/ArcoCoreTests/*.swift`, `AppUITests/ArcoFlowTests.swift`.

| Requisito | Estado | Evidencia | Prueba | Pendiente |
|---|---|---|---|---|
| T01 Precarga sin series realizadas | probado en simulador | borradores `pending` | `draftsAreNotDone`, UI `testLogSetSurvivesRelaunch` | — |
| T02 Confirmar no duplica | probado con datos simulados | ID estable del borrador | `confirmIdempotentAndFailure` | — |
| T03 Cerrar y reabrir conserva sesión | probado en simulador | base en disco, `activeSession` | `persistsOnDisk`, UI relanzamiento | iPhone |
| T04 Fallo de escritura | probado con datos simulados | guardado inyectable, vuelve a borrador | `confirmIdempotentAndFailure` | — |
| T05 Editar/borrar recalcula | probado con datos simulados | récords y gráficas desde registros | `editRecalculates` | — |
| T06 Cambiar plantilla no altera historial | probado con datos simulados | — | `templateChangeKeepsHistory` | — |
| T07 Calentamiento excluido | probado con datos simulados | — | `warmupAndAttendance` | — |
| T08 RIR vacío válido | probado con datos simulados | RIR opcional en borrador | pruebas de repositorio | — |
| T09–T11 D/I/F, papel único, unión de grupo | probado con datos simulados | `MuscleCounter` | `MuscleCounterTests` | — |
| T12–T13 Pares unilaterales | probado con datos simulados | `bodyExposures` (corregido) | `ReviewRegressionTests`, `unilateralThroughRepository` | — |
| T14–T17 Atribuciones conservadoras | probado con datos simulados | matriz v1.0 | `MuscleCounterTests` | — |
| T18 Versión de atribución | parcial | versión guardada por serie y visible | — | no hay recálculo con otra versión (solo existe v1.0) |
| T19 Sugerencia explicada con datos | probado con datos simulados | evidencia por región y fechas | `explanationCitesData` | ver en simulador con historial real |
| T20 Sin ejercicio apto | probado con datos simulados | — | `SuggestionTests` | — |
| T21 Rechazar sugerencia | implementado sin probar | "Mantener mi elección"; nunca edita la selección | — | — |
| T22 Sin historial, sin diagnóstico | probado con datos simulados | regla de concentración | `noDataNoSuggestion` | — |
| T23–T24 Unidades y mancuernas | probado con datos simulados | convención por ejercicio | `UnitsTests`, `unilateralThroughRepository` | — |
| T25 Máquinas/variantes separadas | probado con datos simulados | comparable = variante + convención | `prefillFromPrevious` | selector de gráfica sin prueba de interfaz |
| T26 Asistencia ≠ fuerza | probado con datos simulados | `isLiftedLoad` (corregido) | `ReviewRegressionTests`, `RecordsTests` | — |
| T27–T33 Progresión, récords, % seguro, sin ceros, semana parcial | probado con datos simulados | — | `RecordsTests`, `ChartTests`, `periods` | — |
| T34 Primera serie crea asistencia | probado en simulador | — | `warmupAndAttendance`, UI | — |
| T35 Un día con varias sesiones | probado con datos simulados | — | `attendanceConsolidation` | — |
| T36 Sesión parcial | probado con datos simulados | — | `partialSession` | — |
| T37 Borrar serie conserva manual | probado con datos simulados | — | `attendanceConsolidation` | — |
| T38 Jueves y domingo descanso | probado con datos simulados | convención única de día (corregido) | `seedAndWeekdays`, `restDaysSkipped`, `restResolution` | — |
| T39 Plan histórico en adherencia | parcial | métricas separadas; sin plan no hay % | `AdherenceMetrics` | **no se guardan versiones del plan**: cambiar la rutina hoy cambia el denominador de las últimas 4 semanas |
| T40 Notificaciones denegadas | implementado sin probar | estado real y enlace a Ajustes | — | iPhone |
| T41 Asistencia cancela revisión del día | probado con datos simulados | planificador por fecha | `attendanceCancelsOnlyThatDay` | entrega real: iPhone |
| T42 Acción dirigida a la fecha del aviso | probado con datos simulados | id `arco.review.AAAA-MM-DD` | `identifierRoundTrip` | acción real: iPhone |
| T43 Posponer sin duplicar ni cruzar día | probado con datos simulados | — | `snooze` | iPhone |
| T44 Sin avisos contradictorios | probado con datos simulados | — | `noContradictions` | iPhone |
| Horarios por día | probado con datos simulados | `ReminderRuleModel` por día | `perDayTimes` | — |
| T45 Bisiesto, año, semana, zona, DST | probado con datos simulados | `CivilDay` | `calendarEdges` | — |
| T46 Sesión cruza medianoche | implementado sin probar | fecha asignada al iniciar | — | prueba específica |
| T47–T48 Cámara denegada / foto privada | requiere iPhone | AVFoundation, cifrado en Vault | — | el simulador no tiene cámara |
| T49–T51 Peso y foto | implementado sin probar | revisión con un pesaje compartido | — | prueba con cámara |
| T52–T54 Peso actual, estimado, borrar último | probado con datos simulados | peso inválido ignorado (corregido) | `ReviewRegressionTests`, `weightValidity`, UI `testWeightValidation` | — |
| T55–T57 IMC y referencia 18+ | probado con datos simulados | — | `BMITests`, `age` | — |
| T58 Altura histórica | probado con datos simulados | `BMIHistory` | `bmiHistory` | — |
| T59 Medidas por lado/protocolo/unidad | implementado sin probar | conversión a la unidad configurada | — | prueba de interfaz |
| T60 PIN incorrecto y limitación | parcial: probado en simulador | — | UI `testVaultPIN` | esperas tras reiniciar y manipular el reloj |
| T61 Face ID cancelado | requiere iPhone | — | — | — |
| T62 Todas las rutas autenticadas | probado en simulador (parcial) | pila desbloqueada separada | UI `testVaultPIN` | rutas desde Perfil con fotos reales |
| T63 Selector de apps oculta la foto | requiere iPhone | `vaultPrivacyScreen` | — | — |
| T64 Olvidé mi PIN | requiere iPhone | `.deviceOwnerAuthentication` | — | — |
| T65 Sin claves ni imágenes legibles fuera | probado con datos simulados (parcial) | archivo sin texto en claro; sin logs | `fullRoundTrip`, `preflight-publico.sh` | archivos del Vault en iPhone |
| T66 Exclusión de copias reaplicada | probado con datos simulados (base) | base, -wal y -shm excluidos (corregido) | `storeExcludedFromBackup` | Vault y base en iPhone |
| T67 Borrar foto y derivados | implementado sin probar | — | — | iPhone |
| T68 Secuencia temporal | implementado sin probar | caché acotada | — | rendimiento en iPhone |
| T69 CSV seguro | probado con datos simulados | — | `CSVTests` | — |
| T70 Contraseña errónea/corrupción no modifican | probado con datos simulados | validación completa antes de escribir | `wrongPassword`, `corruptedPhotoChunk`, `truncatedOrTampered` | — |
| T71 Restaurar en instalación limpia con nuevas claves | probado con datos simulados | fotos recifradas con otra clave | `fullRoundTrip` | exportar/importar archivo real en iPhone |
| T72 Reimportar sin duplicar | probado con datos simulados | — | `reimportDoesNotDuplicate` | — |
| T73 Migración v1 → v2 | probado con datos simulados | `ArcoMigrationPlan` | `migrationFromV1` | — |
| T74 Claro/oscuro/texto grande/VoiceOver | parcial: probado en simulador | capturas oscuro + texto XL | UI `testDarkModeAndLargeText` | VoiceOver, Reducir movimiento/transparencia |
| T75 Sin conexión | implementado sin probar | sin código de red (verificado por inspección) | — | prueba en modo avión |
| T76 Primera apertura sin datos demo | probado en simulador | — | UI `testFirstLaunchHasNoDemoData` | — |
| Sin temporizador de descanso | verificado por inspección | solo el temporizador de cámara | `grep` sin coincidencias | — |
| Copia que describe su contenido | probado en simulador | "Fotos: no" y opción desactivada con la bóveda bloqueada | UI `testBackupDescribesContentHonestly` | — |
