# Arco — Decisiones y supuestos

## Técnicas
1. **Núcleo como Swift Package (`ArcoCore`)** + app iOS (`Arco.xcodeproj`) que lo consume.
   Razón: permite probar las reglas de negocio con `swift test` sin simulador, cumpliendo la
   exigencia de "cálculos verificables" de forma rápida y determinista.
2. **SwiftData** para persistencia (iOS 18+). Modelos `@Model` en el target de app; los value
   types de dominio viven en ArcoCore y son `Sendable`. Datos derivados recalculables.
3. **Swift 6 language mode**, data-race safety. `@MainActor` solo para UI/estado observable.
4. **`.xcodeproj` con grupos sincronizados de sistema de archivos** (Xcode 16+): el pbxproj no
   enumera cada Swift; apunta a carpetas. Reduce fragilidad al añadir ficheros.
5. **Objetivo iOS 18.0**. iPhone 14 lo soporta. APIs iOS 26+ (Liquid Glass) NO se adoptan salvo
   petición; se usan materiales nativos estándar con respeto a Reducir transparencia.

## Producto (resuelven ambigüedades sin inventar datos personales)
- **Unidades por defecto**: kg y cm, editables. No es afirmación sobre el gimnasio (spec §2).
- **Conteo fraccional**: F = D + 0,5·I como convención agregada etiquetada, no garantía (§10.1).
- **Agregación de grupos musculares**: crédito del padre = máximo de los hijos por serie, unión
  de series, nunca suma (§10.2).
- **e1RM**: SÍ se implementa con Epley, filtrado a 2–10 reps, carga externa positiva y RIR 0–1
  declarado; etiquetado como estimación, secundario. Para 1 rep real se usa carga observada.
  Fuera de ese filtro no se produce indicador (§12, E13).
- **IMC**: marco adulto NHS/NICE 18+, bandas <18,5 / 18,5–<25 / 25–<30 / ≥30. Clasifica sobre
  valor sin redondear; muestra 1 decimal (§18, B01/B02).
- **Tendencia de peso**: promedio de pesajes medidos por fecha, luego media de medias diarias de
  7 días calendario; se muestra con ≥3 fechas con medición (§18).
- **Fotos**: bóveda privada en contenedor de la app, cifrada (AES-GCM, clave 256 bits en Keychain
  `WhenUnlockedThisDeviceOnly`), excluida de backup, protección de archivo completa. PIN de 4
  dígitos con verificador derivado + sal (no es la clave de cifrado de las fotos). Face ID opcional.
  NO se escribe en Apple Fotos ni álbum Ocultos (§16, §17).
- **Sin temporizador de descanso** en ninguna parte (§25). Temporizador de cámara sí permitido.
- **Rutina**: 5 días (lun empuje, mar tirón, mié pierna+abdomen, vie superior+antebrazo, sáb
  pierna+abdomen). Jue y dom descanso. Selección flexible, favoritos reutilizables (§2).

## Supuestos explícitos (anotados, no inventados como datos del propietario)
- Fecha de nacimiento, altura, peso, metas, rangos de reps: se piden en la app (onboarding).
  No se precargan valores. Edad derivada de fecha real.
- Pesos de barra / incrementos de máquina: desconocidos por defecto, configurables por ejercicio.

## Pendiente de decisión del propietario (no bloquea)
- Nombre definitivo de la app (ahora "Arco", configurable).
- Firma de código para instalar en iPhone (requiere su Apple ID / equipo en Xcode).

## 2026-11-03 — Inicio del seguimiento y fecha de inicio de entrenamiento
- La primera versión del plan rige desde el primer uso de Arco (o desde el registro más antiguo
  si hay datos restaurados), no "desde siempre". Los días anteriores no cuentan como planificados
  ni aparecen como "sin registro": se muestran como "Antes de usar Arco". Alternativa descartada:
  vigencia ilimitada hacia atrás, que contaba como pendientes días en que la app no existía.
- La fecha en que el usuario empezó a entrenar (maestro §2) se pide opcionalmente en la
  configuración y se guarda como preferencia local que viaja en la copia. Es informativa y no
  altera la asistencia. Alternativa descartada: un esquema v4 solo para este dato.

## 2026-11-03 — Restauración sobre datos existentes (segunda revisión)
- Combinar por registro (sesión, ejercicio de sesión, serie, ejercicio del catálogo, etc.) en
  lugar de omitir lo que ya existe. Solo se decide sin preguntar cuando los datos permiten ordenar
  las versiones: valores de fábrica del catálogo frente a valores del usuario, hora de confirmación
  de una serie frente a su borrador, y cierre de sesión (definitivo). El resto son conflictos que
  se resuelven con la opción elegida por el usuario antes de restaurar, tras ver la previsión.
- Se añadió "Reemplazar con la copia" con segunda confirmación; nunca borra fotos ni ejercicios
  del catálogo. Alternativa descartada: guardar marcas de modificación o registros de borrado,
  que exigía un esquema v4 y no ayudaba con las copias ya creadas.
- Las copias nuevas guardan fechas con milisegundos (`datePrecision = "ms"`); el lector acepta las
  anteriores en segundos. El número de formato sigue en 2.
- Ver tabla completa en `10-SEGUNDA-REVISION.md`.

## 2026-11-03 — Borradores y ejercicios al restaurar (tercera revisión)
- Combinar nunca descarta borradores: si la copia cerró una sesión que aquí tiene borradores
  propios, la sesión queda abierta y el usuario decide. Alternativa descartada: pedir una
  confirmación específica para descartarlos; conservar es más simple y no pierde nada, y quien
  quiera el estado exacto de la copia tiene "Reemplazar".
- Reemplazar no borra ejercicios del catálogo que la copia no tiene: se nombran en la previsión,
  la confirmación y el resultado. Alternativa descartada: borrarlos (dejaría historiales o
  plantillas sin ejercicio) u ofrecer un reemplazo "exacto" del catálogo.
