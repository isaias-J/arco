# Arco — Pendientes y próxima acción

Última actualización: 2026-11-03, cierre de las etapas de `08-ETAPAS.md`.

## Estado verificado
- `cd ArcoCore && swift test`: 97 pruebas / 16 suites en verde.
- XCUITest en el simulador aislado "Arco-QA": 14 recorridos en verde.
- Build de la app sin errores.
- Todas las funciones obligatorias del maestro §3 tienen implementación; las que dependen de
  hardware están en `09-VERIFICACION-IPHONE.md`.
- `scripts/preflight-publico.sh` sin hallazgos antes de publicar.

## Próxima acción concreta
Instalar en el iPhone y recorrer `09-VERIFICACION-IPHONE.md`. Anotar cada resultado en
`03-PRUEBAS.md` cambiando el estado a "probado en iPhone real".

## Pendiente de desarrollo (no bloquea el uso)
1. Interfaz para recalcular con otra versión de atribución (T18) cuando exista una v1.1 (hoy solo hay v1.0).
2. Ilustraciones propias de cada pose (hoy símbolos genéricos).
3. Exportación con muchas fotos fuera del hilo principal, con progreso.
4. Pruebas automáticas de `PhotoVaultOperations` (vínculo foto-peso y borrado).
5. Pruebas de interfaz de incremento/barra por ejercicio y del editor de atribución personalizada
   (la lógica está probada en el núcleo).
6. T46 (sesión que cruza medianoche): sin prueba específica.

## Bloqueos
- Firma para el iPhone: requiere tu Apple ID en Xcode.
