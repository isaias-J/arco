# Arco — Etapas de cierre contra la lista obligatoria (spec §3)

Método: cada etapa es pequeña, se prueba de principio a fin, se registra aquí y se publica.
Al retomar: leer el prompt maestro, este archivo y `04-PENDIENTES.md`; comprobar `git log` y
`swift test`; continuar en la primera etapa no marcada como hecha.

## Auditoría de partida (2026-11-03)
Funciones obligatorias de §3 sin implementar o incompletas al empezar:
| §3 | Requisito | Situación inicial |
|---|---|---|
| 2 | Catálogo: archivar, renombrar, alias sin perder registros (§6) | faltaba |
| 3 | Plantillas semanales editables; sustituir y reordenar ejercicios | faltaba editar rutina, sustituir y reordenar |
| 6 | Corregir atribuciones de ejercicios personalizados (§10.4) | faltaba |
| 9 | Doble progresión configurable por ejercicio (§13) | solo lógica |
| 10 | Plan histórico en la adherencia (T39) y rachas (§14) | faltaba |
| 11 | Resumen semanal opcional en avisos | sin interfaz |
| 14 | Resumen semanal y motivación con datos reales | faltaba |
| §9 | Biblioteca de fuentes consultable con alcance y fecha | faltaba |
| §7 | Incrementos y peso de barra por ejercicio | sin interfaz |
| §2 | Fecha de inicio de entrenamiento pedida en la configuración | faltaba (detectado en la verificación final) |

## Etapas
| # | Etapa | Estado | Pruebas |
|---|---|---|---|
| 1 | Esquema v3 aditivo (progresión, versiones de plan, atribución personalizada) + migración | hecho | `migrationV2toV3`; copia v3 en `fullRoundTrip` |
| 2 | Catálogo: archivar, renombrar, alias, atribución personalizada, incremento y barra | hecho | `catalogEdits`, `customAttribution`; UI `testCatalogRenameAndArchive` |
| 3 | Rutina editable con historial; adherencia por plan vigente en cada fecha; rachas | hecho | `planHistoryAdherence`, `beforeTrackingStartIsNeutral`, `streak`; UI `testRoutineEditAppliesFromToday` |
| 4 | Sesión: reordenar y sustituir ejercicios | hecho | `substituteAndMove`; UI `testSubstituteInSession` |
| 5 | Doble progresión configurable y aviso "cumpliste tu regla" | hecho | `doubleProgression`; UI `testDoubleProgressionMessage` |
| 6 | Resumen semanal y motivación; aviso semanal | hecho (aviso real: iPhone) | `summaryMessages`; UI `testEvidenceAndSummary` |
| 7 | Biblioteca de fuentes y método de atribución | hecho | `EvidenceLibraryTests`; UI `testEvidenceAndSummary` |
| 8 | Recorridos de interfaz nuevos, verificación contra el maestro, lista para iPhone | hecho | 14 recorridos UI; `09-VERIFICACION-IPHONE.md` |

## Registro
- Núcleo de etapas 1–6: 94 pruebas en verde.
- Interfaz de etapas 2–7 (catálogo, editor de rutina, sustituir/subir/bajar en sesión, regla de
  doble progresión, resumen semanal en Hoy y Progreso, aviso semanal opcional, Fuentes y método).
- Recorridos UI nuevos: de 6, 3 fallaban al principio. Causas encontradas y corregidas:
  - Sugerencias: la prueba dependía del día real (martes = espalda/bíceps, sin hombro). Ahora
    edita la rutina para que hoy incluya hombros. Además "Mantener mi elección" se marcó
    `.borderless` para que el toque no lo capture la fila completa de la lista.
  - Catálogo: el teclado seguía abierto tras "Guardar nombre" y tapaba "Archivar". **Arreglo en
    la app:** guardar nombre, alias, carga o regla cierra el teclado.
  - Doble progresión: los campos numéricos no tenían identificador y el toque caía en la etiqueta.
    Se añadieron identificadores y la prueba toca el campo editable.
  - Las pruebas escribían "4040" al no borrar el valor precargado; ahora comprueban que el campo
    contiene exactamente lo escrito.
- **Corrección de lógica detectada al revisar capturas:** el resumen decía "Asistencia: 0 de 1"
  el primer día de uso porque contaba el lunes anterior a instalar la app. La versión inicial del
  plan ahora rige desde el primer uso (o desde el registro más antiguo si se restauró una copia).
  Los días anteriores aparecen como "Antes de usar Arco", neutros. Prueba `beforeTrackingStartIsNeutral`.
- **Hueco del maestro §2 cerrado:** la configuración inicial pide (opcional) cuándo empezaste a
  entrenar; se edita en Perfil → Datos personales y viaja en la copia. Prueba UI
  `testTrainingStartAskedInOnboarding`.
- Estado final: `swift test` 97 pruebas / 16 suites en verde; XCUITest 14/14 en verde en "Arco-QA".

## Próxima acción
Instalar en el iPhone y recorrer `SEGUIMIENTO/09-VERIFICACION-IPHONE.md`.
