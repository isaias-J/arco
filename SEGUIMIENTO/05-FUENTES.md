# Arco — Registro de fuentes y atribuciones musculares

Versión de reglas de atribución: **v1.0** (ExerciseCatalog.attributionVersion).

## Honestidad de los indicadores (spec §9)
Arco distingue cuatro tipos de información y no los confunde:
1. **Dato observado**: carga, repeticiones, series, fechas, medidas, fotos.
2. **Dato calculado**: IMC, conteos, conversiones, tendencias.
3. **Estimación**: aporte indirecto, e1RM, cobertura regional.
4. **Heurística de producto**: orden de sugerencias, umbrales, reglas de progresión.

No se usan términos como "garantizado", "crecimiento medido" ni "1RM real". El factor 0,5 del
conteo fraccional es una convención agregada etiquetada (E02), no una garantía por ejercicio.

## Fuentes de entrenamiento (consultar antes de traducir a regla)
- **E01** ACSM 2026 — Overview of reviews (volumen/esfuerzo/individualización, adultos sanos).
- **E02** Pelland et al. 2026 — dosis-respuesta volumen/frecuencia (justifica directa/indirecta
  y el modelo fraccional; NO valida media serie para todos los sinergistas).
- **E03** Robinson et al. 2024 — proximidad al fallo (contexto, sin obligar al fallo).
- **E04** Refalo et al. 2023 — proximidad al fallo (no superioridad general del fallo).
- **E05** Vigotsky et al. 2018 — rendimiento vs hipertrofia (medidas distintas).
- **E06** Schoenfeld et al. 2019 — conteo de series en multiarticulares (no tabla universal).
- **E07** Vigotsky et al. 2018 — EMG no predice crecimiento.
- **E08** Kassiano et al. 2022 — variación organizada (base de las sugerencias).
- **E09** Kinoshita et al. 2026 — single vs multi-joint (no transferir protocolo de prensa).
- **E10** Maeo et al. 2023 — tríceps overhead vs neutral (especificidad regional).
- **E11** Kinoshita et al. 2023 — pantorrilla de pie vs sentado.
- **E12** IUSCA 2021 — recomendaciones de programación.
- **E13** RCP/NRAP 2025 — fórmula de Epley (verificación de la fórmula, no exactitud universal).

## IMC
- **B01** NHS — calculadora adulta 18+, fórmula y límites por masa muscular.
- **B02** NICE NG246 — referencias de IMC.
- **B03** CDC — marco adulto desde 20 (se documenta por qué Arco usa NHS 18+, no CDC).

Fórmula: IMC = peso(kg) / altura(m)². Bandas <18,5 / 18,5–<25 / 25–<30 / ≥30. Clasificación
sobre el valor sin redondear; presentación con un decimal.

## Matriz de atribución inicial (conservadora, v1.0)
Implementada en `ArcoCore/Sources/ArcoCore/Science/ExerciseCatalog.swift`. D=directo,
I=indirecto, U=desconocido/depende. Los músculos no listados no reciben crédito automático
(eso NO afirma ausencia fisiológica). Puntos clave verificados por pruebas:
- Pulldown brazos extendidos: dorsales D, sin bíceps (T14).
- Prensa sentada: cuádriceps D, sin isquiotibiales automáticos (T15).
- Curl invertido: flexores del codo D + braquiorradial D (región), sin muñeca directa (T16).
- Peck deck: pectoral D, sin deltoides anterior automático.
- Fondos sentados en máquina: tríceps D; pecho y delt anterior U (no copiar fondos libres).

Documentación de Apple consultada para servicios del sistema: notificaciones [A01, A02],
captura y permisos [A03], LocalAuthentication [A04], Keychain [A05], protección de archivos
[A06], privacidad en segundo plano [A07], exclusión de backup [A08], materiales [A09],
accesibilidad [A10, A11], firma personal [A12], álbum Ocultos de Fotos [A13].
