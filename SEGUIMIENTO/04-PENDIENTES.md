# Arco — Pendientes y próxima acción

Última actualización: 2026-11-02, cierre de la revisión integral.

## Estado verificado
- `cd ArcoCore && swift test`: 86 pruebas en verde.
- XCUITest en el simulador aislado "Arco-QA": 7 recorridos en verde.
- Build de la app sin errores.
- Repositorio público actualizado; `scripts/preflight-publico.sh` sin hallazgos.
- El ajuste del Mac `com.apple.CrashReporter DialogType` se restauró a su valor por defecto.

## Próxima acción concreta
Instalar en el iPhone 14 (README §4) y recorrer la lista del README §7. Anotar cada resultado
en `03-PRUEBAS.md` cambiando el estado a "probado en iPhone real".

## Pendiente de desarrollo
1. Historial de versiones del plan semanal (T39).
2. Interfaz para recalcular con otra versión de atribución (T18) cuando exista una v1.1.
3. Ilustraciones propias de cada pose.
4. Exportación con muchas fotos fuera del hilo principal con progreso.
5. Pruebas automáticas de `PhotoVaultOperations` (vínculo foto-peso y borrado).

## Bloqueos
- Firma para el iPhone: requiere tu Apple ID en Xcode.
