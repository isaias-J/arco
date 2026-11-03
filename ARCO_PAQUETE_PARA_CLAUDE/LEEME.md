# Entrega para construir Arco

El archivo principal es **ARCO_PROMPT_MAESTRO.md**. Contiene el contexto completo, las decisiones del propietario, el alcance, el catálogo, las reglas de negocio, el diseño, las fuentes y los criterios de aceptación.

## Cómo usarlo

1. Coloca el contenido de este paquete en la carpeta donde quieras que Claude construya la aplicación. Conserva la carpeta `referencias` junto al documento.
2. Abre Claude en esa carpeta y entrégale esta instrucción:

> Lee ARCO_PROMPT_MAESTRO.md completo y revisa las tres imágenes de la carpeta referencias como inspiración visual. Construye la aplicación siguiendo el encargo, conserva estas decisiones durante todo el trabajo y ejecuta las verificaciones descritas. Empieza inspeccionando el entorno y continúa hasta una entrega funcional. Distingue lo implementado, lo probado y lo que requiera comprobación manual en mi iPhone.

3. Los datos que todavía no has proporcionado —fecha de nacimiento, altura, peso, unidades del gimnasio, series y repeticiones habituales— se configuran dentro de la aplicación. Claude no debe inventarlos.

## Decisiones importantes incorporadas

- Registro por serie con valores reutilizables y confirmación rápida.
- Cinco días semanales; elección flexible de ejercicios y sugerencias explicables para repartir énfasis.
- Prensa de piernas sentada con asiento móvil; fondos sentados de empuje hacia abajo; presses libres con barra.
- RIR opcional y sin temporizador de descanso.
- Conteo directo, indirecto y fraccional, con límites y fuentes identificados.
- Fotos en bóveda privada local, fuera de Apple Fotos, con PIN y Face ID opcional. Sin sincronización automática.
- Peso y fotografía opcionalmente vinculados; medidas corporales con gráficos.
- IMC adulto con marco NHS/NICE aplicable desde los 18 años, identificado y contextualizado.
- Asistencia, calendario anual y recordatorios locales por día.
- Archivo cifrado exportable por decisión expresa, con restauración verificable.
- Gráficos, diseño claro/oscuro, accesibilidad y 76 escenarios de aceptación.

El documento es una especificación y un prompt; no incluye una aplicación ya implementada ni afirma que sus pruebas se hayan ejecutado.

Las referencias científicas orientan el diseño. El aporte de una serie a cada músculo es una estimación dependiente del ejercicio y su variante, no una medición exacta garantizada.
