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

## Etapas
| # | Etapa | Estado | Pruebas |
|---|---|---|---|
| 1 | Esquema v3 aditivo (progresión, versiones de plan, atribución personalizada) + migración | hecho (núcleo) | `migrationV2toV3`; copia v3 en `fullRoundTrip` |
| 2 | Catálogo: archivar, renombrar, alias, atribución personalizada, incremento y barra | núcleo hecho; interfaz pendiente | `catalogEdits`, `customAttribution` |
| 3 | Rutina editable con historial; adherencia por plan vigente en cada fecha; rachas | núcleo hecho; interfaz pendiente | `planHistoryAdherence`, `streak` |
| 4 | Sesión: reordenar y sustituir ejercicios | núcleo hecho; interfaz pendiente | `substituteAndMove` |
| 5 | Doble progresión configurable y aviso "cumpliste tu regla" | núcleo hecho; interfaz pendiente | `doubleProgression` |
| 6 | Resumen semanal y motivación; aviso semanal | núcleo hecho; interfaz pendiente | `summaryMessages` |
| 7 | Biblioteca de fuentes y método de atribución | pendiente | |
| 8 | Recorridos de interfaz nuevos, verificación contra el maestro, lista para iPhone | pendiente | |

## Registro
- Núcleo de etapas 1–6: `swift test` → 94 pruebas en verde (8 nuevas en `StageClosureTests`, copia ampliada con datos v3).

## Próxima acción
Interfaz de las etapas 2–6 (catálogo, rutina, sesión, progresión, resumen) y de la etapa 7.
