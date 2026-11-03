# Arco — Correcciones de la segunda revisión independiente

Revisión hecha sobre `472b41e` (informe `SEGUNDA_REVISION_ARCO.md`, pruebas
`PRUEBAS_SEGUNDA_REVISION_ARCO.swift`). Al empezar, el árbol estaba limpio y en ese commit.

## Línea base y reproducción
- Antes de cambiar código: `swift test` → 97 pruebas en verde.
- Las dos pruebas independientes se copiaron sin cambios a
  `ArcoCore/Tests/ArcoCoreTests/IndependentRestoreAuditTests.swift` y **fallaron** con 4
  expectativas (nombre y archivado del catálogo; estado y repeticiones de la serie), igual que
  en el informe. Tras la corrección pasan sin modificarlas.

## 1 y 2. Restauración: política de combinación y conflictos
Código: `ArcoCore/Sources/ArcoCore/Persistence/ArchiveMerge.swift` (motor) y
`ArchiveTransfer.swift` (importador). Pantalla: `App/Arco/Views/Profile/BackupView.swift`.

Antes de cambiar nada, la app calcula qué haría cada opción con los datos actuales (sin
escribir) y lo muestra. Opciones:

| Opción | Qué hace |
|---|---|
| **Combinar (recomendado)** | Añade lo que falta. Adopta los cambios de la copia que se pueden ordenar con los datos guardados. En un conflicto real conserva lo de este iPhone. No borra nada. |
| **Combinar; en conflictos, usar la copia** | Igual, pero en los conflictos aplica la copia. No borra nada. |
| **Reemplazar con la copia** | Deja entrenamientos, medidas, asistencia, catálogo, perfil y rutina como en la copia y elimina lo que la copia no tiene. Pide una segunda confirmación que enumera lo que se eliminará. **Nunca borra fotos.** |

Reglas (iguales en la previsión y en la restauración real):

| Caso | Resultado |
|---|---|
| Registro idéntico | Sin cambios ("ya están aquí"). |
| Solo en la copia | Se añade. Excepción: borradores (series sin realizar) para una sesión que ya existe aquí no se añaden; se cuentan como "borradores no añadidos". |
| Solo en este iPhone | Se conserva al combinar; se elimina al reemplazar. Los ejercicios del catálogo y las fotos nunca se eliminan. |
| Ejercicio preinstalado: aquí con valores de fábrica, en la copia cambiado | Se aplica la copia, campo a campo (nombre, alias, equipo, patrón, instrucciones, archivado). Arregla el hallazgo 1. |
| Ejercicio: la copia trae el valor de fábrica y aquí se cambió | Se conserva lo de aquí (la copia no aporta cambios). |
| Ejercicio: ambos cambiados de forma distinta, o personalizado distinto | Conflicto. |
| Nombre de la copia ya usado aquí por otro ejercicio | No se aplica nunca (no se fusionan historiales); se informa. |
| Serie: borrador aquí y realizada en la copia con hora de confirmación posterior | Se adopta la copia (confirmar estampa la hora real). Arregla el hallazgo 2. |
| Serie: realizada aquí y borrador en la copia (copia antigua) | Se conserva lo de aquí. |
| Serie: omitida en un lado y borrador en el otro | Gana la omitida (solo se omite desde un borrador). |
| Serie: mismas horas con distinto estado (p. ej. deshacer confirmación) o realizada en ambos con valores distintos (edición) | Conflicto: los datos no permiten saber cuál es posterior. |
| Serie eliminada aquí (borrado lógico) y realizada en la copia | Conflicto: al combinar conservando este iPhone sigue eliminada. |
| Sesión abierta aquí y cerrada en la copia | Se adopta el cierre (en Arco cerrar es definitivo) y se descartan los borradores locales que la copia no tiene, igual que al finalizar. |
| Sesión cerrada aquí y abierta en la copia | Se conserva lo de aquí. |
| Fecha u hora de la sesión distintas | Conflicto. |
| Ejercicio de sesión sustituido por otro distinto en cada lado | Conflicto. Las series realizadas nunca se reasignan a otro ejercicio: con series hechas aquí no se aplica la copia salvo al reemplazar. |
| Ajustes de carga: aquí vacíos (desconocido) y en la copia con valor | Se completan con la copia. |
| Pesaje sin foto aquí y con foto vinculada en la copia | Se adopta el vínculo. |
| Asistencia automática | Se recalcula desde las series combinadas; si ambos lados tienen la de la misma sesión, no se duplica el día. |
| Récords, gráficas, conteos, sugerencias y metas | No se guardan: se recalculan desde los registros. |

Límites honestos:
- **Borrados físicos**: borrar un pesaje, un borrador o un registro de asistencia no deja rastro.
  Al combinar una copia anterior, ese registro vuelve (aparece como añadido). Para dejar el
  iPhone exactamente como la copia está "Reemplazar".
- **Divergencia en dos dispositivos**: si se confirma la misma serie en dos iPhone, la regla de
  la hora posterior adopta la confirmación más tardía.
- **Fechas**: las copias nuevas guardan milisegundos (`datePrecision = "ms"`). Las anteriores,
  segundos; con ellas la comparación de horas usa segundos enteros y dos acciones dentro del
  mismo segundo se tratan como conflicto.

Transacción: se valida contraseña e integridad de todo el archivo antes de tocar nada; todo se
aplica en un único guardado; si algo falla se deshacen los cambios y se borran las fotos ya
escritas. Las fotos se siguen recifrando con la clave local.

Mensaje final: "Restauración terminada." solo si nada de la copia quedó fuera; si hubo
conflictos conservando este iPhone o borradores no añadidos dice "terminada con diferencias" y
los cuenta.

Pruebas: `IndependentRestoreAuditTests` (2) y `RestoreMergeTests` (16): instalación limpia con
catálogo sembrado; ejercicios preinstalados modificados y archivados; personalizados; conflictos
con cada estrategia; cambio local conservado; nombre ocupado; copia antigua→reciente y al revés;
restauración repetida (también sobre el propio origen); edición distinta en cada lado; series
nuevas en ambos lados; sesión cerrada en la copia; borradores en sesión cerrada; borrado lógico y
reemplazo (con previsión = resultado); reemplazo que conserva fotos y limpia vínculos; asistencia
sin duplicar; formato anterior (fechas en segundos, sin campos v3); fallo de guardado a mitad
(sin datos ni fotos a medias); contraseña incorrecta sobre datos existentes; previsión idéntica
al resultado. Recorrido UI `testExportAndRestoreReport`: exporta con el selector de Archivos,
contraseña incorrecta sin cambios, previsión "ya están aquí", reemplazo con segunda
confirmación, combinación con mensaje honesto.

## 3. Gráficas históricas
- **Series por músculo en el tiempo** (`MuscleHistoryView`, núcleo `MuscleHistory`): grupo o
  región; semanas (12), meses (12) o años (5); método directas, directas e indirectas apiladas o
  estimación fraccional, con explicación. Pares izquierda/derecha cuentan una exposición; el
  grupo usa la unión, no la suma de regiones. Periodo en curso o que empieza antes del primer
  registro atenuado e indicado como "incompleto". Periodo sin series registradas = raya y "sin
  registros" (no cero); con asistencia manual sin series se dice "asistencia sin series"; un
  periodo con entrenamiento pero sin series de ese músculo sí es cero. Tabla accesible.
- **Repeticiones por sesión** (en el detalle de cada ejercicio, núcleo `RepsHistory`): misma
  combinación comparable (ejercicio, variante y convención); criterio "misma carga: X" (por
  defecto, la carga repetida en más sesiones) o "serie más pesada de cada sesión" (avisa de que la
  carga cambia). Con asistencia no se ofrece "más pesada". Lados por separado. Sesiones sin esa
  carga no aparecen (no son cero). Calentamientos fuera. Tabla con la carga de cada punto.
- Pruebas: `ProgressHistoryTests` (8) con datos conocidos, meses/años, límites, parciales,
  sin registros frente a cero, unilateralidad, libras y lados. UI: `testMuscleHistory`,
  `testRepsHistory`, `testHistoryDarkLargeText`.

## 4. Poses
`App/Arco/Views/Photos/PoseIllustration.swift`: ilustraciones originales dibujadas en código
(sin imágenes de terceros) para frontal relajado, lateral, espalda, doble bíceps frontal y bíceps
de perfil, con pasos breves. Aparecen en la lista de poses, en la "Guía de poses" y sobre la
vista previa de la cámara (con "Cómo colocarte" / "Menos"); la cuadrícula y la superposición de
la foto anterior siguen igual y nada de esto entra en la foto. Las poses personalizadas siguen
con un símbolo genérico. Comprobado en simulador con capturas (`testPoseGuide`); **sobre la
cámara real solo se puede ver en el iPhone**. Son siluetas esquemáticas: orientan el encuadre,
no corrigen la postura.

## 5. Correcciones anteriores
Se volvieron a ejecutar sus pruebas: fotos incluidas y recifradas (`fullRoundTrip`), días de la
rutina y avisos (`seedAndWeekdays`, `perDayTimes`, planificador), acciones de aviso por fecha
(`identifierRoundTrip`, `attendanceCancelsOnlyThatDay`), primera serie y asistencia sin duplicar
(`warmupAndAttendance`, `attendanceConsolidation`, nuevo `attendanceNotDuplicated`), pares
unilaterales, asistencia de máquina fuera de cargas, peso inválido (`ReviewRegressionTests`),
exclusión de copias (`storeExcludedFromBackup`), PIN (UI). No se tocó bóveda, PIN, Face ID ni
exclusión de copias.

## 6. PIN con y sin firma
- Con la firma habitual del simulador ("Sign to Run Locally"): `testVaultPIN` pasa, también en
  la corrida completa de 19 recorridos.
- Con `CODE_SIGNING_ALLOWED=NO`: falla en la misma comprobación que vio la revisión (tras
  "Guardar" no aparece el campo de desbloqueo). Ese binario solo lleva la firma del enlazador
  (`Identifier=Arco`, Info.plist sin vincular, sin recursos sellados), mientras que el habitual
  se identifica como `com.arco.app`. El PIN se guarda en el Llavero; es probable que la
  diferencia de firma afecte al Llavero, pero **no se demostró**: los registros del simulador no
  mostraron un error del Llavero. Conclusión: probar siempre con la firma habitual.
