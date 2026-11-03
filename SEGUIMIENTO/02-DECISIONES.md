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
