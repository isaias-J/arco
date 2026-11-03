# Arco — Pendientes y próxima acción

Última actualización: 2026-11-03, tras la segunda revisión independiente
(`10-SEGUNDA-REVISION.md`).

## Estado verificado
- `cd ArcoCore && swift test`: 123 pruebas / 19 suites en verde (incluidas las 2 independientes,
  que antes fallaban).
- XCUITest en simulador temporal aislado: 19 recorridos en verde en una sola corrida con la
  firma habitual del simulador.
- Build de la app sin errores. `scripts/preflight-publico.sh` sin hallazgos antes de publicar.

## Próxima acción concreta
Instalar en el iPhone y recorrer `09-VERIFICACION-IPHONE.md` con datos ficticios primero.
Anotar cada resultado en `03-PRUEBAS.md` como "probado en iPhone real".

## Implementado pero pendiente de prueba en iPhone
- Ilustración de pose sobre la vista previa de la cámara.
- Restauración real de una copia con fotos desde Archivos tras reinstalar.
- Cámara, Face ID, "Olvidé mi PIN", avisos reales, selector de apps, VoiceOver, modo avión.

## Pendiente de desarrollo (no bloquea el uso)
1. Interfaz para recalcular con otra versión de atribución (T18) cuando exista una v1.1.
2. Exportación con muchas fotos fuera del hilo principal, con progreso.
3. Pruebas automáticas de `PhotoVaultOperations` (vínculo foto-peso y borrado).
4. Pruebas de interfaz de incremento/barra por ejercicio y del editor de atribución personalizada.
5. T46 (sesión que cruza medianoche): sin prueba específica.
6. Registro de borrados físicos (pesajes, borradores, asistencia manual): sin él, combinar una
   copia anterior puede devolver un registro borrado; "Reemplazar" es la alternativa exacta.
7. La causa exacta del fallo del PIN con la firma desactivada no está demostrada.

## Bloqueos
- Firma para el iPhone: requiere tu Apple ID en Xcode.
