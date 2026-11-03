# Correcciones de la revisión independiente (2026-11-02)

Fuente: `INFORME_REVISION_ARCO.md` (17 hallazgos) y `PRUEBAS_REVISION_ARCO.swift` (3 pruebas,
integradas sin cambios en `ArcoCore/Tests/ArcoCoreTests/ReviewRegressionTests.swift`: fallaban
antes y pasan ahora). Copia previa: `../arco-backups/arco-pre-revision-20261102-2236.tgz`.

## Estado de cada hallazgo
| # | Hallazgo | Estado | Corrección | Prueba |
|---|---|---|---|---|
| 1 | La copia no incluía fotos | Corregido | Formato portable v2: cada foto es un fragmento cifrado; la opción solo se activa con la bóveda abierta y el texto dice si hay fotos | `fullRoundTrip`, `withoutPhotos`, UI `testBackupDescribesContentHonestly` |
| 2 | Restauración parcial | Corregido | Perfil, ajustes, rutina, recordatorios, ejercicios personalizados, preferencias, metas, descansos, fotos; validación completa antes de escribir; transacción con limpieza | `fullRoundTrip`, `reimportDoesNotDuplicate`, `corruptedPhotoChunk` |
| 3 | Días desplazados | Corregido | Convención única `Weekday` (Calendar, 1 = domingo); los datos guardados ya la usaban: sin migración | `seedAndWeekdays`, `restDaysSkipped`, `restResolution` |
| 4 | Avisos no conectados | Corregido (falta iPhone) | Planificador por fecha, delegado con acciones, categorías registradas, reconciliación al abrir/registrar/responder | `ReminderPlannerTests` |
| 4b | Horario único | Corregido | Horario y minutos por día y por categoría, persistidos | `perDayTimes` |
| 5 | Registro de series incompleto | Corregido | Precarga de la sesión comparable, borradores persistentes, editar, borrar con deshacer, calentamiento, RIR opcional, lados, convención y variante por ejercicio; sin temporizador | `RepositoryIntegrationTests`, UI `testLogSetSurvivesRelaunch` |
| 5b | UUID nuevo por intento | Corregido | El borrador tiene un ID estable | `confirmIdempotentAndFailure` |
| 6 | Sugerencias sin interfaz | Corregido | Tarjetas en la selección con explicación, "Añadir" y "Mantener mi elección" | `explanationCitesData` (lógica) |
| 7 | Pares unilaterales duplicados | Corregido | `bodyExposures` empareja izquierda/derecha | prueba independiente 1 |
| 8 | Seguimiento semanal / braquiorradial | Corregido | Conteo por músculo y periodo, metas por método, detalle; braquiorradial en antebrazo | `periods`, `goals`, `brachioradialisInForearm` |
| 9 | Base no excluida de copias | Corregido (falta iPhone) | Base, -wal y -shm excluidos en cada arranque | `storeExcludedFromBackup` |
| 10 | Gráficas mezclan cargas | Corregido | Asistencia fuera de "mayor carga"; selector variante + convención | prueba independiente 2 |
| 11 | Peso inválido | Corregido | Peso actual y tendencia ignoran valores ≤ 0; validación en todos los formularios | prueba independiente 3, UI `testWeightValidation` |
| 12 | Peso/IMC/perfil | Corregido | Gráficos de peso e IMC, edición del perfil, historial de altura, medidas convertidas de unidad | `bmiHistory`, `age` (lógica) |
| 13 | Foto sin peso | Corregido (falta iPhone) | Revisión con un pesaje compartido, vincular el último sin duplicar | sin prueba (requiere cámara) |
| 14 | PIN y borrado | Corregido (falta iPhone) | "Olvidé mi PIN" con autenticación del sistema; borrado de foto y derivados | UI `testVaultPIN` (PIN) |
| 15 | "Hoy descansé" vacío | Corregido | Guarda la resolución, cancela la revisión, se puede deshacer | `restResolution`, UI `testRestResolution` |
| 16 | Documentación sobrestimada | Corregido | Matriz rehecha con estados precisos (`03-PRUEBAS.md`) | — |
| 17 | Carrera al crear la clave | Corregido (sin prueba) | Ante duplicado se relee la clave guardada | requiere Keychain de dispositivo |

## Problemas nuevos encontrados y corregidos durante la revisión
- **Causa real de los fallos de SwiftData en pruebas:** el `ModelContainer` se liberaba antes que
  su contexto. Con el contenedor retenido, las pruebas de integración funcionan bajo `swift test`.
- **Navegación de Hoy:** al empezar, la sesión no se abría (mezcla de enlaces por destino y por
  valor). Lo detectó la prueba de interfaz; ahora la pila usa rutas explícitas.
- **Tarjetas estrechas:** las tarjetas se ajustaban al contenido en lugar de ocupar el ancho.
- **Prueba inestable:** SwiftData no garantiza el orden de las relaciones; la prueba buscaba por índice.
- **PIN entre reinstalaciones:** el PIN vive en Keychain y sobrevive a borrar la base (comportamiento
  de iOS). Las pruebas de interfaz lo limpian con el argumento de prueba.
- **Cámara cerrada por la alerta de permiso:** la bóveda se bloqueaba en estado `.inactive`; ahora
  cubre en `.inactive` y bloquea en segundo plano.
- **Datos de prueba con aspecto personal y referencias de terceros** en el repositorio público:
  retirados (ver `07-SEGURIDAD.md`).

## Decisiones y supuestos
- Convención de día de `Calendar` en todo el proyecto.
- Esquema SwiftData versionado (v1 publicado, v2 aditivo) con migración ligera explícita.
- La restauración combina por identificador; con la opción marcada sustituye perfil, ajustes,
  rutina y recordatorios. No borra nada de lo actual.
- Las copias v1 (solo datos, sin fotos) no se pueden restaurar desde la interfaz: la app no llegó
  a instalarse en el iPhone, así que no deberían existir.
- Ventana de avisos de 28 días; si la app no se abre en ese tiempo, los avisos se detienen.
- Sugerencias solo cuando otra región del mismo grupo recibió más trabajo directo en 14 días.

## Limitaciones abiertas
- **Plan histórico (T39):** no se guardan versiones de la rutina; cambiarla altera el cálculo
  de cumplimiento de las últimas 4 semanas.
- **Ilustraciones de poses:** se usan símbolos genéricos, no ilustraciones propias.
- **Recalcular con otra versión de atribución (T18):** no hay interfaz (solo existe v1.0).
- Todo lo que depende de cámara, Face ID, Keychain real, entrega de avisos y rendimiento con
  muchas fotos está sin verificar hasta probarlo en el iPhone.
