# Arco — Correcciones de la tercera revisión independiente

Revisión sobre `78c4c83` (informe `TERCERA_REVISION_ARCO.md`, pruebas
`PRUEBAS_TERCERA_REVISION_ARCO.swift`). Árbol limpio al empezar.

## Reproducción
Las dos pruebas del revisor se copiaron sin cambios y **fallaron** (125 pruebas, 2 fallos):
1. "Combinar" eliminaba un borrador local con 15 kg × 9 cuando la copia traía cerrada esa sesión,
   aunque la pantalla decía "No borra nada".
2. "Reemplazar" conservaba un ejercicio añadido después, aunque la pantalla decía que el catálogo
   quedaba "exactamente como en la copia", y la previsión no lo mencionaba.

## Política final
**Borradores al combinar.** Combinar (en sus dos variantes) ya no elimina nada, tampoco
borradores. Si la copia trae cerrada una sesión que aquí sigue abierta con borradores que la copia
no tiene, no se adopta el cierre: la sesión queda abierta, los borradores se conservan con sus
pesos y repeticiones y se registra un conflicto que lo explica. Las series realizadas de la copia
sí se incorporan. Si no hay borradores locales que proteger, el cierre se adopta como antes.
- Previsión: "Se conservarán N borradores de este iPhone (con sus pesos y repeticiones); sus
  sesiones quedan abiertas aunque la copia las cerró", más el conflicto con la fecha de la sesión.
- Resultado: "Se conservaron N borradores…; sus sesiones siguen abiertas…".
- Las sesiones que solo están aquí se informan con sus series y borradores ("Solo están en este
  iPhone y se conservan: 1 sesiones, 1 borradores sin realizar").

**Reemplazar.** Sigue eliminando lo que la copia no tiene, ahora contando aparte "borradores sin
realizar", y lo dice en rojo en la previsión y en la segunda confirmación. Los ejercicios del
catálogo que la copia no tiene **no se borran nunca** (podrían dejar historiales sin ejercicio):
la explicación ya no dice "exactamente como en la copia", y la previsión, la confirmación y el
resultado los nombran (hasta 5), indicando si son personalizados o preinstalados y cuántas
sesiones los usarán después de restaurar, con la sugerencia de archivarlos en Catálogo.

**Otro arreglo encontrado al probar.** Tras "Crear copia cifrada" el teclado quedaba abierto en
el campo de repetir contraseña y tapaba la barra de pestañas. Ahora se cierra al exportar.

## Pruebas
- `ArcoCore/Tests/ArcoCoreTests/ThirdAuditTests.swift`: mismos escenarios del revisor, adaptados
  a la política final.
  - Prueba original 1 esperaba que reemplazar borrase el ejercicio. Se cambió la expectativa: se
    conserva, la previsión y el resultado lo nombran (`keptExtraExercises`) y no figura como
    eliminado. Prueba nueva: un ejercicio extra se informa con 0 sesiones tras reemplazar (la
    sesión local que lo usaba se elimina) y con 1 al combinar.
  - Prueba original 2 (combinar conserva el borrador) se mantiene igual en su expectativa y pasa.
    Se amplió: en las dos variantes de combinar la previsión no elimina nada y avisa de 2
    borradores protegidos; el resultado coincide con la previsión; la sesión sigue abierta; y con
    "Reemplazar" la previsión anuncia los 2 borradores, el resultado coincide y se eliminan.
- `cd ArcoCore && swift test` → **126 pruebas / 20 suites en verde**.
- Recorrido UI `testExportAndRestoreReport` ampliado: tras exportar se abre una sesión con
  borradores; la previsión de combinar no muestra eliminaciones y dice que la sesión y sus
  borradores se conservan; la de reemplazar muestra en rojo "Se ELIMINARÁN… 1 sesiones,
  1 borradores sin realizar" y la confirmación lo repite; combinar termina sin "Eliminado" y la
  sesión sigue abierta. Pasa en un simulador temporal aislado con la firma habitual.
