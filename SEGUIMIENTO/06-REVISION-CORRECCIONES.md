# Correcciones de la revisión independiente (2026-11-02)

Fuente: `INFORME_REVISION_ARCO.md` (17 hallazgos) y `PRUEBAS_REVISION_ARCO.swift` (3 pruebas).
Copia previa a las correcciones: `../arco-backups/arco-pre-revision-20261102-2236.tgz`.

## Verificación inicial
- Código idéntico al revisado (sin cambios posteriores). Las 3 pruebas independientes se
  integraron en `ArcoCore/Tests/ArcoCoreTests/ReviewRegressionTests.swift` sin modificar sus
  expectativas y fallaron: 6≠3 (pares), 40 kg de asistencia en gráfica, peso −1 kg actual.
- Causa real de los crashes de SwiftData en pruebas anteriores: `ModelConfiguration` sin
  `cloudKitDatabase: .none` (modo automático) dentro del ejecutable de pruebas. Con `.none`
  los contenedores en memoria y en disco funcionan bajo `swift test`. Se reintroducen pruebas
  de integración de SwiftData.

## Plan de trabajo (estado)
| # | Hallazgo | Estado |
|---|----------|--------|
| 7 | Pares unilaterales duplicados | corregido en núcleo |
| 10 | Asistencia como carga en gráfica | corregido en núcleo; falta filtro por convención en UI |
| 11 | Peso inválido como actual | corregido en núcleo; falta validación en UI |
| 8 | Braquiorradial agrupado en bíceps | corregido (grupo antebrazo) |
| 3 | Días de la semana desplazados | en curso |
| 1, 2 | Respaldo sin fotos / restauración parcial | pendiente |
| 9 | Base no excluida de copias | pendiente |
| 4, 15 | Avisos no conectados / "Hoy descansé" vacío | pendiente |
| 5 | Registro de series incompleto | pendiente |
| 6 | Sugerencias sin UI | pendiente |
| 8 | Seguimiento semanal por músculo y metas | pendiente |
| 12, 13 | Peso/IMC/perfil/foto-peso | pendiente |
| 14 | Recuperar PIN y borrar fotos | pendiente |
| 17 | Carrera al crear clave de bóveda | pendiente |
| 16 | Documentación sobrestimada | pendiente (al final) |

## Decisiones
- Convención única de día de la semana: la de `Calendar` (1 = domingo … 7 = sábado). Los
  valores ya guardados en `RoutineTemplateModel.weekday` usan esa convención (lunes = 2), por
  lo que no hace falta migrar datos: se corrigen los lectores y el comentario erróneo.
- Esquema versionado (`VersionedSchema` + plan de migración explícito). Cualquier cambio en un
  modelo existente debe congelar su forma anterior dentro de la versión previa.
