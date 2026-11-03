# ARCO — Prompt maestro de implementación

Versión 1.0 · Especificación preparada el 2 de noviembre de 2026.

Este documento es un encargo completo para implementar una aplicación. Se puede entregar directamente a Claude en una terminal. Las decisiones del propietario están incorporadas; las propuestas técnicas y heurísticas están identificadas para no confundirlas con resultados científicos.

---

## 1. Encargo, resultado y forma de trabajar

Actúa como responsable de producto, desarrollador sénior de aplicaciones nativas para iPhone, diseñador de interfaces y responsable de calidad. Construye **Arco**, una aplicación personal para registrar entrenamiento de hipertrofia, observar el progreso y mantener la motivación. El nombre es provisional y configurable.

Implementa una aplicación funcional, persistente, cuidada y utilizable en un iPhone real. El resultado debe incluir proyecto de Xcode, código fuente, recursos, documentación de instalación, pruebas relevantes y una explicación honesta de lo que verificaste. Un conjunto de pantallas estáticas o un prototipo con información simulada no satisface este encargo.

Primero inspecciona el repositorio y las instrucciones locales aplicables. Si ya existe una aplicación, conserva su trabajo válido y adapta esta especificación a ella. Si el repositorio está vacío, crea el proyecto. Verifica las versiones reales de Xcode, Swift, SDK e iOS disponibles antes de fijar dependencias y configuración.

Trabaja por etapas verificables, pero continúa hasta completar el alcance de la primera versión. Mantén una lista persistente de requisitos y pendientes para conservar el contexto en trabajos largos. Pregunta únicamente cuando falte una decisión que impida avanzar de forma segura; las preferencias rutinarias deben resolverse con los criterios de este documento y quedar anotadas. Si no puedes compilar o probar una función por limitaciones del entorno, especifica qué falta, sin afirmar que pasó.

No publiques la app, no contrates servicios ni introduzcas cuentas externas como parte de esta implementación. La entrega debe permitir al propietario compilarla, instalarla y probarla en su iPhone desde su Mac.

### Prioridades, en orden

1. Registro de series rápido y fiable, incluso sin conexión.
2. Conservación correcta del historial y cálculos verificables.
3. Privacidad de fotos y datos personales.
4. Visualización clara del progreso.
5. Sugerencias explicables de selección de ejercicios.
6. Diseño atractivo, animaciones discretas y accesibilidad.

Si una decisión visual dificulta registrar una serie o leer un dato, simplifica esa decisión visual. Si una sugerencia parece precisa pero la evidencia no permite sostenerla, reduce su precisión y explica su alcance.

## 2. Contexto del propietario y decisiones ya tomadas

- Tiene 19 años, está próximo a cumplir 20 y lleva aproximadamente tres semanas entrenando de forma constante al definir el proyecto. No inventes fecha de nacimiento ni fecha exacta de inicio: se solicitan durante la configuración.
- Dispone de iPhone 14 y Mac, ambos actualizados según su declaración. Comprueba las versiones instaladas cuando tengas acceso al entorno.
- Primera versión para uso personal; arquitectura preparada para ampliarse sin introducir ahora infraestructura innecesaria.
- Interfaz en español. Fechas, números y unidades adaptables a la configuración regional, sin deducir nacionalidad o etnia.
- Rutina semanal de cinco días: lunes empuje, martes tirón, miércoles pierna y abdomen, viernes tren superior y antebrazo, sábado pierna y abdomen. Jueves y domingo son descanso planificado.
- El catálogo de ejercicios es estable, pero el propietario elige variantes según sus preferencias de cada día.
- Quiere sugerencias para repartir el énfasis entre zonas musculares a lo largo de distintas sesiones, siempre dentro de su catálogo y respetando su elección.
- Se registran peso y repeticiones de cada serie, con valores de referencia precargados y confirmación explícita de realización.
- Se acepta RIR opcional. **No incluir temporizador de descanso, cuenta regresiva ni controles relacionados**: el propietario administra sus descansos.
- Fotos privadas con PIN de cuatro dígitos y Face ID opcional.
- Almacenamiento local; sin sincronización automática, servidor, cuenta ni envío de fotos a servicios externos.
- Interpretar la solicitud de fotos “ocultas” como una bóveda privada dentro de la app, fuera de la fototeca. No escribir automáticamente en el álbum Ocultos de Apple Fotos: este pertenece a la fototeca y puede sincronizarse según los ajustes del sistema. Esta decisión satisface la intención de privacidad y almacenamiento local.
- Peso corporal y foto vinculables, pero una foto es opcional al guardar un peso. Una foto puede invitar a registrar peso, marcarlo como estimado o permitir omitirlo.
- Tres poses base y poses adicionales opcionales, incluidas poses de bíceps.
- Calendario anual de asistencia y revisión nocturna configurable, con posibilidad de posponer.
- IMC con referencia adulta aplicable desde 18 años, identificando el marco utilizado; medidas corporales con gráficos.
- Seguimiento por ejercicio y músculo, resúmenes semanales, récords y doble progresión opcional.
- Tema claro, oscuro y del sistema. Predeterminado: seguir el sistema. Identidad de azules, curvas y profundidad sutil.

### Datos todavía no proporcionados

No inventes pesos, altura, fecha de nacimiento, género, medidas, series habituales, rangos de repeticiones, horarios ni metas. Las unidades iniciales serán kg y cm como preferencia editable, no como afirmación sobre el gimnasio. Los campos de configuración permiten elegir lb y otras unidades compatibles.

Como no existe una rutina exacta por ejercicio, usa plantillas por grupos musculares y una selección guiada del catálogo. Permite guardar como favorita la selección realizada para reutilizarla. No cargues todos los ejercicios del catálogo en cada sesión.

## 3. Alcance funcional y límites de la primera versión

### Obligatorio

1. Configuración inicial breve, editable y reanudable.
2. Catálogo inicial y ejercicios personalizados.
3. Plantillas semanales, selección flexible, sustitución y reordenación de ejercicios.
4. Sesión activa con registro rápido, persistencia inmediata y recuperación tras cierre.
5. Historial de series, variantes, sesiones y modificaciones.
6. Conteo de series directas, indirectas y estimadas, con trazabilidad.
7. Sugerencias explicables de cobertura y énfasis muscular.
8. Gráficos por ejercicio, músculo y periodo.
9. Récords y doble progresión configurable, sin subidas obligatorias.
10. Asistencia automática y manual; calendario anual y cumplimiento del plan.
11. Recordatorios locales editables por día y revisión nocturna.
12. Bóveda de fotos, captura guiada, comparación y secuencia temporal interna.
13. Perfil, peso, altura, IMC y medidas corporales con historial y gráficos.
14. Resumen semanal y motivación basada en datos reales.
15. Exportación de entrenamiento y archivo local cifrado opcional para recuperar datos.
16. Diseño adaptable, accesible y verificado en iPhone 14.
17. Pruebas de reglas de negocio, persistencia, seguridad y flujos principales.

### Opcional dentro de la interfaz, sin bloquear el flujo principal

- RIR por serie; se puede configurar que solo se solicite en la última serie, sin copiarlo a las demás.
- Notas, cansancio y molestias autodeclaradas; nunca obligatorios.
- Medidas corporales y lateralidad.
- Poses adicionales y metas configuradas por el usuario.
- Sugerencias de doble progresión.

### Ampliaciones fuera de esta primera versión

Apple Salud, Apple Watch, nutrición, calorías, red social, rankings externos, suscripciones, entrenador por IA, análisis automático del cuerpo, estimación de grasa por fotografía y exportación de vídeo. Deja separaciones de arquitectura razonables para integraciones futuras; no presentes botones sin funcionalidad ni solicites permisos para funciones ausentes.

La reproducción temporal de fotos sí es obligatoria, pero será una secuencia dentro de la app y no requerirá crear un vídeo.

## 4. Arquitectura propuesta

Usa Swift y SwiftUI para una app nativa de iPhone. Como punto de partida, considera iOS 18 o posterior, Swift Charts y persistencia local con SwiftData o Core Data. Decide según el entorno real y documenta una elección distinta. Usa APIs modernas con comprobaciones de disponibilidad. Los efectos específicos de sistemas recientes deben tener una presentación alternativa legible.

Separa como mínimo:

- Dominio: unidades, reglas de series, sesiones, asistencia, progresión y mediciones.
- Persistencia: repositorios, transacciones, migraciones y recuperación.
- Servicios: notificaciones, cámara, autenticación, cifrado, archivos y exportación.
- Analítica: agregaciones y modelos derivados puros y verificables.
- Presentación: vistas y estado de interfaz.
- Datos científicos: fuentes, reglas y atribuciones musculares versionadas.

Evita un único archivo con toda la lógica, dependencias de red para funciones locales y abstracciones extensas sin necesidad. Prefiere frameworks de Apple. Cualquier dependencia externa debe tener necesidad concreta, licencia compatible y mantenimiento comprobado.

Inyecta reloj, calendario, zona horaria, autenticación, cámara y programador de notificaciones para poder probar reglas sin depender de hardware o de la hora real.

La información derivada se recalcula a partir de los registros originales. Una caché nunca es la única copia de datos. Usa identificadores estables, operaciones idempotentes y migraciones explícitas; no recrees la base de datos ante un error de migración.

## 5. Modelo de datos mínimo

Diseña entidades equivalentes a las siguientes. Los nombres pueden variar, pero deben conservar sus responsabilidades.

| Entidad | Contenido y reglas |
|---|---|
| UserProfile | Identidad local opcional, fecha de nacimiento real, experiencia autodeclarada, preferencias y objetivo descriptivo. Sin cuenta remota. |
| AppSettings | Idioma, unidades, tema, inicio de semana, ajustes de notificaciones y privacidad. |
| ExerciseDefinition | ID estable, nombre, alias, equipo, patrón, instrucciones breves, tipo de carga, origen inicial/personalizado, estado archivado. |
| ExerciseVariant | Agarre, inclinación, recorrido declarado, unilateralidad, máquina concreta y convenciones que afectan la comparación. |
| EquipmentProfile | Alias local de máquina, carga nominal, peso conocido de barra, incrementos disponibles; valores desconocidos explícitos. |
| MuscleNode | Jerarquía de grupos y regiones, evitando equivalencias anatómicas falsas. |
| AttributionRule | Variante, músculo, papel directo/indirecto/no contabilizado/desconocido, versión, justificación, fuentes y nivel de soporte. |
| RoutineTemplate | Grupos del día y selección preferida opcional. Versiones o instantáneas para no reescribir el pasado. |
| ScheduleEntry | Día planificado, descanso, cambios puntuales y vigencia histórica. |
| WorkoutSession | Inicio, fin, estado, fecha de entrenamiento asignada, zona de origen y plantilla utilizada. |
| SessionExercise | Ejercicio y variante fijados para esa sesión, orden e instantánea de ajustes relevantes. |
| SetRecord | ID, carga original y normalizada, unidad, repeticiones, tipo, estado, lado, RIR opcional, fechas y versión de atribución. |
| AttendanceEvent | Fecha de entrenamiento, procedencia automática/manual y relación con sesiones. |
| AttendanceResolution | Descanso puntual, ausencia confirmada, sin confirmar o recordatorio pospuesto. |
| BodyWeightEntry | Fecha de medición, fecha de ingreso, valor, unidad, medido/estimado, procedencia y vínculo opcional con foto. |
| HeightEntry | Fecha y altura; historial para interpretar correctamente mediciones antiguas. |
| BodyMeasurementEntry | Tipo, lado, protocolo, valor, unidad y fecha. |
| PhotoCheckIn | Fecha, pose, archivo privado, orientación, espejo y vínculo opcional a una medición de peso. |
| WeeklyGoal | Músculo, objetivo elegido, método de conteo, vigencia y procedencia. |
| ReminderRule | Categoría, día, horario, excepciones, zona horaria y habilitación. |
| EvidenceSource | Referencia verificable, enlace, año, tipo, alcance y fecha de revisión. |
| RecommendationSnapshot | Sugerencia, datos que la generaron, versión de reglas, explicación y respuesta del usuario. |

Puedes agregar un registro de revisiones o borrado lógico si aporta recuperación. Debe existir borrado definitivo de fotos y datos solicitado por el usuario. No retengas imágenes eliminadas en una papelera oculta sin informar.

### Tiempo e historial

Guarda instantes absolutos para eventos, además de la fecha civil asignada al entrenamiento y la zona de origen. Un viaje no debe mover silenciosamente los entrenamientos pasados a otro día.

Para sesiones que crucen medianoche, conserva por defecto la fecha de inicio elegida para el entrenamiento y permite corregirla. Conserva también las horas reales de las series para las vistas de tiempo transcurrido. La fecha de registro de un dato antiguo no sustituye a su fecha de medición.

## 6. Catálogo inicial y normalización de ejercicios

Carga los siguientes 27 ejercicios o familias. Un alias compartido no debe crear duplicados del mismo movimiento; una diferencia relevante de equipo o técnica debe poder crear una variante con historial distinguible.

| ID sugerido | Nombre inicial | Aclaraciones confirmadas o configurables |
|---|---|---|
| chest_incline_barbell | Press inclinado con barra | Barra de banca; ángulo editable. No inventar ángulo ni peso de barra. |
| chest_flat_barbell | Press plano con barra | Barra de banca clásica del gimnasio. Confirmar peso antes de sumarlo. |
| chest_pecdeck | Peck deck en máquina | Apertura de pecho. Distinto del modo posterior de la misma máquina. |
| chest_machine_press | Press de pecho en máquina, plano/ligeramente declinado | El propietario describe una posición ligeramente declinada. No convertirla en un ángulo medido ni en aislamiento de “pecho inferior”. |
| shoulder_lateral_raise | Elevaciones laterales | Equipo configurable; conservar variante de mancuernas/polea/máquina. |
| shoulder_overhead_press | Press militar | Equipo y posición por confirmar; no asumir barra. |
| shoulder_front_raise | Elevaciones frontales | Equipo configurable. |
| shoulder_reverse_pecdeck | Posterior de hombro en peck deck inverso | Máquina compartida con pecho, movimiento e historial distintos. |
| shoulder_facepull | Face pull | Agarre y ejecución influyen en la atribución. |
| triceps_seated_dip | Fondos en máquina sentada | Confirmado: empuje hacia abajo sentado. No son fondos asistidos de peso corporal. |
| triceps_pushdown | Extensión de tríceps en polea / pushdown | Agarre configurable. |
| triceps_skullcrusher | Extensión acostada / skull crushers | Equipo y recorrido configurables. |
| back_pulldown | Jalón al pecho / pulldown | Agarre convencional configurable. |
| back_machine_row | Remo en máquina | Guardar alias de máquina y orientación de codos cuando se conozca. |
| back_straight_arm_pulldown | Pulldown con brazos extendidos en polea | Confirmado: movimiento de brazos desde arriba hacia la cintura, con codos relativamente fijos. |
| back_neutral_pulldown | Jalón al pecho con agarre neutro | Variante específica, no duplicar como ejercicio idéntico al jalón sin diferenciar agarre. |
| curl_preacher | Curl predicador | Equipo configurable. |
| curl_hammer | Curl martillo | Convención de peso por mancuerna y lado explícita. |
| curl_reverse | Curl invertido | Agarre pronado; participa el antebrazo. |
| curl_bayesian | Curl bayesian en polea | Variante unilateral o bilateral explícita. |
| curl_dumbbell | Curl con mancuernas | Alterno/simultáneo y supinación configurables. |
| legs_extension | Extensión de cuádriceps | Máquina, unilateralidad y carga nominal. |
| legs_seated_leg_press | Prensa de piernas sentada con asiento móvil | Confirmado: pies apoyados, se desplaza el asiento. No es hack, Smith ni sentadilla. |
| legs_seated_curl | Curl femoral sentado | Flexión de rodilla; máquina concreta. |
| legs_calf_raise | Elevaciones de pantorrilla | Rodilla extendida/flexionada y equipo por seleccionar. |
| abs_leg_raise | Elevaciones de piernas | Equipo y forma de movimiento configurables. |
| abs_machine_crunch | Abdominales en máquina | Flexión de tronco si corresponde a la ejecución. |

Permite crear ejercicios, archivar, renombrar y gestionar alias sin perder registros. No elimines historial por archivar. Una corrección de nombre no tiene por qué dividir una serie histórica; una diferencia mecánica relevante sí requiere identificar la variante.

Las instrucciones de cada ejercicio serán breves y descriptivas. Evita prescripciones de técnica agresivas, diagnósticos de molestias o mensajes que obliguen a entrenar con dolor.

## 7. Carga, repeticiones y convenciones de comparación

### Carga

- Diferencia peso externo, peso nominal de máquina, asistencia, peso corporal y ejercicio sin carga registrada.
- Guarda unidad original y normaliza para cálculos: 1 lb = 0,45359237 kg. Evita redondeos acumulativos.
- Cambiar la unidad de visualización no altera el registro original.
- Acepta incrementos configurables por ejercicio; no supongas que todas las máquinas aumentan de 2,5 en 2,5 kg.
- Barra: convención predeterminada “peso total incluyendo barra”. Si se ofrece calculadora de discos, pide el peso real de la barra; no deduzcas 20 kg por su apariencia.
- Mancuernas: mostrar “kg por mancuerna”. No duplicar el peso máximo mostrado. Una métrica secundaria de carga total, si existe, debe explicar cuándo incluye ambas mancuernas.
- Máquina: conservar valor indicado y alias de equipo; no interpretarlo como fuerza real transmitida ni compararlo entre máquinas distintas.
- Asistencia: una cifra mayor puede significar menor dificultad; nunca premiarla automáticamente como más fuerza.
- Peso corporal: registrar repeticiones y lastre opcional. No convertir todo el peso corporal en carga desplazada para cualquier ejercicio.
- Carga 0 puede ser válida en un ejercicio sin lastre; no usarla para representar un campo desconocido.

### Repeticiones y estados

- Repeticiones: entero positivo para una serie completada normal. Una serie fallida sin repeticiones puede conservarse como intento, excluido del conteo principal.
- No convertir automáticamente entradas vacías en cero.
- Tipos mínimos: calentamiento, trabajo e intento. Estados: pendiente, completada, omitida o eliminada.
- Una serie de trabajo completada con datos válidos es elegible para conteo; RIR desconocido no la invalida.
- “Sesión parcial”, “serie indirecta fraccional” y “repetición de recorrido parcial” son conceptos distintos. No uses una sola bandera para los tres.
- Drop sets, rest-pause y otras técnicas avanzadas quedan fuera del flujo principal. Si el usuario las registra como nota, no inventes equivalencias automáticas con series normales.

### Validación de entradas

| Dato | Regla |
|---|---|
| Carga | Número finito, no negativo cuando el tipo lo permite; unidad y convención obligatorias. Diferenciar desconocido y cero. |
| Repeticiones | Entero positivo para completar una serie normal; intento fallido como estado distinto. |
| RIR | Opcional; cero o categoría no negativa. Permitir “4 o más” y “no sé” sin convertirlos en valores exactos. No aceptar negativos ni inferir un número de una categoría abierta. |
| Peso, altura y perímetros | Valores positivos y finitos. Advertir y pedir confirmación ante cambios extraordinarios, sin corregirlos silenciosamente ni imponer límites fisiológicos inventados. |
| Fecha de nacimiento | Fecha pasada real; calcular edad con calendario. No inferirla del contexto de este documento. |
| Mediciones | No registrar una medición futura como ya realizada. Una fecha pasada introducida hoy conserva ambas fechas. |
| Objetivos | Enteros no negativos para series directas; valores compatibles con la resolución de 0,5 para metas fraccionales; vigencia y método explícitos. |
| Decimales | Interpretar separador de la configuración regional y validar formatos ambiguos; no convertir “2,5” en 25. |
| Nombres | Recortar espacios, conservar tildes y permitir alias; detectar duplicados sin fusionar historiales automáticamente. |

Los límites técnicos para archivos o campos se documentan como protección de recursos, no como afirmaciones biológicas.

### Unilateralidad

Una serie izquierda y una derecha constituyen un par bilateral cuando el ejercicio se registra por lados. Tres pares representan tres exposiciones por lado, no seis series para el mismo músculo del cuerpo completo. Mantén análisis por lado cuando difieran.

Si solo se hace un lado, regístralo así: no imputes el otro. No mezcles el modo “par” con filas por lado para contar dos veces. Muestra claramente qué convención está activa y conserva su versión en la sesión.

## 8. Flujo de entrenamiento y velocidad de registro

### Pantalla Hoy

Mostrar fecha, rutina sugerida por el plan, sesión activa si existe y acceso principal a empezar/reanudar. Después, un resumen breve de constancia y una o dos señales útiles. En descanso planificado mostrarlo con naturalidad y permitir entrenamiento opcional.

Al empezar: presentar selección favorita o última selección compatible con el día. Permitir aceptar, cambiar, quitar y añadir ejercicios del catálogo. No hacer un interrogatorio antes de cada entrenamiento.

### Sesión activa

Para cada ejercicio:

- Nombre y variante claramente visibles.
- Último registro comparable con fecha; si pertenece a una sesión distinta, decirlo.
- Filas de series con peso, repeticiones, RIR opcional y marca de completada.
- Copiar valores útiles de la sesión comparable anterior como borrador.
- Botones grandes para modificar solo lo que cambió.
- Confirmar una serie en un toque cuando los valores sean correctos.
- Añadir serie, duplicar valores, deshacer, editar y omitir.
- Acceso discreto a historial y sustitución.

Objetivo de aceptación: cuando los valores estén precargados correctamente, confirmar y guardar una serie requiere un toque; modificar un único campo y confirmar debe poder hacerse en pocos segundos en pruebas de uso. No garantices un tiempo medido sin realizar la prueba.

Persistir cada confirmación sin esperar al botón “finalizar”. La interfaz debe distinguir guardado correcto y error real. Si falla la escritura, conservar el borrador, indicar la situación y permitir reintentar sin crear duplicados.

Al reabrir después de cierre, bloqueo o interrupción: recuperar sesión, ejercicios, series completadas, borradores y posición razonable de navegación. No iniciar otra sesión automáticamente.

### Finalización

Mostrar series de trabajo, ejercicios realizados y récords comprobados. Permitir finalizar una sesión parcial sin inventar las series pendientes. Ofrecer guardar la selección de ejercicios para ese tipo de día. Una sesión abandonada con trabajo real no pierde ese trabajo.

No insertar formularios de perfil, fotos, temporizadores, encuestas largas ni recomendaciones extensas entre dos series.

## 9. Fundamento científico y honestidad de los indicadores

Las referencias están en la sección 24. Deben existir en la app como una biblioteca breve y consultable, con enlaces, alcance y fecha de revisión. Diferencia:

1. Dato observado: carga, repeticiones, series, fechas, medidas y fotos.
2. Dato calculado: IMC, conteos, conversiones y tendencias.
3. Estimación: aporte indirecto, fuerza máxima estimada y cobertura regional.
4. Heurística de producto: orden de sugerencias, umbral para una observación o regla de progresión.

No uses “certificado”, “garantizado”, “crecimiento medido” o “recuperación exacta” para describir estas estimaciones. No muestres diagnósticos, porcentajes de músculo ganado por las cargas, grasa estimada por fotografías, predicción de altura ni promesas de crecimiento por edad.

La evidencia sobre adultos sanos orienta el producto, pero no prueba una dosis óptima individual. El volumen puede favorecer hipertrofia con rendimientos decrecientes; la proximidad al fallo aporta contexto y no obliga a llegar al fallo. El registro de fuerza es una medida de rendimiento, distinta de una medida directa de hipertrofia. [E01, E02, E03, E04, E05]

## 10. Conteo muscular: modelo, atribuciones y límites

### 10.1 Método de conteo

Ofrece simultáneamente:

- Series directas: número de series de trabajo elegibles clasificadas como directas para un músculo.
- Series indirectas: número real de series elegibles clasificadas como indirectas.
- Estimación fraccional: directas + 0,5 × indirectas.
- Series con atribución desconocida: identificadas aparte.

El factor 0,5 es una convención respaldada como modelo agregado por E02. **No es una garantía de que cada ejercicio aporte exactamente media serie a cada músculo de cada persona.** La revisión E06 muestra que el problema depende del movimiento y de la evidencia disponible. No transfieras coeficientes a todos los sinergistas ni conviertas activación EMG en porcentajes de crecimiento. [E02, E06, E07]

Definición formal para músculo m, periodo P y conjunto S de series elegibles:

- D(m,P) = suma de 1 cuando el papel de m en s sea directo.
- I(m,P) = suma de 1 cuando el papel sea indirecto.
- F(m,P) = D(m,P) + 0,5 × I(m,P).
- U(m,P) = series relevantes cuya atribución para m está sin resolver.

Una serie tiene un único papel por músculo en una versión de reglas; no se suma directa e indirecta para el mismo músculo. No exige que los créditos entre músculos sumen uno: una serie puede trabajar varios músculos. Tampoco se suman músculos para obtener “series totales del entrenamiento”. El total de sesión cuenta identificadores únicos de series realizadas.

### 10.2 Jerarquía y doble conteo

Separa al menos pectoral, deltoides anterior/lateral/posterior, dorsales, retractores escapulares, flexores del codo, tríceps, antebrazo, cuádriceps, isquiotibiales, glúteos, pantorrillas y abdomen.

“Espalda”, “hombros” y “pierna” pueden ser agrupaciones visuales. Para agregarlas, usa la unión de series: una serie que alcance dos regiones de hombro no cuenta dos veces en el grupo hombros. Para el crédito de un padre, toma el mayor crédito de sus hijos por serie, sin sumar sus créditos. Documenta esta regla como decisión del producto. No presentes la suma de subregiones como una dosis biológica total.

En el brazo, etiqueta el conteo general como “bíceps / flexores del codo” y permite inspeccionar los músculos. No atribuyas toda la carga de un martillo o un curl invertido exclusivamente al bíceps braquial. El braquiorradial puede aparecer en una vista anatómica de antebrazo, sin duplicar series en un total corporal.

### 10.3 Matriz inicial conservadora

La tabla es un modelo inicial de atribución basado en función del movimiento y evidencia relacionada, no una tabla de coeficientes clínicamente validados por ejercicio. Debe verificarse, versionarse y mostrarse con sus límites. D = directo; I = indirecto; U = depende de variante o falta información. Los músculos no listados no reciben crédito automático; eso no afirma que no participen.

| Ejercicio/familia | Atribución inicial para conteo | Énfasis cualitativo y precauciones |
|---|---|---|
| Press inclinado con barra | Pectoral D; tríceps I; deltoides anterior I | Registrar inclinación. Etiqueta de orientación clavicular, sin coeficiente regional preciso. |
| Press plano con barra | Pectoral D; tríceps I; deltoides anterior I | No acreditar deltoides lateral ni posterior por defecto. |
| Peck deck de pecho | Pectoral D | Deltoides anterior sin crédito automático en el modelo conservador. |
| Press de pecho en máquina | Pectoral D; tríceps I; deltoides anterior I | La inclinación ligera no crea un músculo “inferior” separado con dosis cuantificada. |
| Elevaciones laterales | Deltoides lateral D | Otras regiones dependen de la variante; no completar hombro anterior/posterior automáticamente. |
| Press militar | Deltoides anterior D; tríceps I; deltoides lateral I provisional | Revisar equipo y trayectoria. Aporte lateral es estimación revisable. |
| Elevaciones frontales | Deltoides anterior D | No acreditar lateral o posterior automáticamente. |
| Peck deck inverso | Deltoides posterior D; retractores escapulares I/U | Depende de cuánto movimiento escapular se realice. |
| Face pull | Deltoides posterior D provisional; retractores escapulares I/U | Rotadores externos como participación cualitativa; no fabricar una dosis de manguito rotador. |
| Fondos sentados en máquina | Tríceps D; pectoral y deltoides anterior U | La máquina concreta y el recorrido importan. No copiar la atribución de fondos libres. |
| Pushdown | Tríceps D | No dividir automáticamente una serie entre sus tres cabezas ni garantizar igual crecimiento. |
| Skull crushers | Tríceps D | Posición del hombro como etiqueta; no asumir equivalencia exacta con extensión overhead del estudio E10. |
| Jalón al pecho y neutro | Dorsales D; flexores del codo I; retractores escapulares I/U | No acreditar posterior de hombro por defecto en todos los agarres. |
| Remo en máquina | Dorsales D provisional; flexores del codo I; retractores escapulares I provisional; posterior de hombro U | Permitir variante con codos abiertos/énfasis escapular que cambie papel principal. No resolver por el nombre de la máquina. |
| Pulldown de brazos extendidos | Dorsales D | No dar media serie de bíceps solo por ser un ejercicio de espalda: no hay flexión dinámica relevante de codo en la variante descrita. |
| Predicador | Flexores del codo D | Equipo y agarre identificados. |
| Curl martillo | Flexores del codo D | Participación braquial/braquiorradial cualitativa; no afirmar aislamiento del bíceps. |
| Curl invertido | Flexores del codo D; braquiorradial D como región | No acreditar flexores/extensores de muñeca como series directas por sujetar la barra. |
| Curl bayesian | Flexores del codo D | Posición del hombro como etiqueta; sin promesa automática de cabeza larga. |
| Curl con mancuernas | Flexores del codo D | Supinación y lateralidad configurables. |
| Extensión de cuádriceps | Cuádriceps D | Puede describirse implicación del recto femoral sin convertirla en multiplicador numérico. |
| Prensa de piernas sentada | Cuádriceps D; glúteos I provisional/U; aductores U | Recorrido y máquina influyen. No otorgar series de isquiotibiales automáticamente. No transferir exactamente el protocolo de E09 a esta máquina. |
| Curl femoral sentado | Isquiotibiales D | No usarlo para afirmar cobertura de todos los patrones de extensión de cadera. |
| Pantorrillas | Pantorrillas D | Rodilla extendida/flexionada permite etiquetas de gastrocnemio/sóleo, con limitaciones de E11. |
| Elevaciones de piernas | Abdomen U; flexores de cadera D como región adicional | Atribución abdominal directa solo para una variante confirmada con flexión de pelvis/tronco pertinente. Si se desconoce, registrar ejecución y no inventar crédito de abdomen. |
| Abdominales en máquina | Abdomen D, si es flexión de tronco | Confirmar tipo de máquina. |

No otorgues crédito automático a antebrazo por cada ejercicio con agarre, al abdomen por estabilizar cualquier levantamiento o a isquiotibiales por toda prensa. Las omisiones del modelo se expresan como “no contabilizado en esta estimación”, no como ausencia fisiológica de actividad.

Para cada fila de atribución conserva: regla, variante, justificación, fuente relacionada, tipo de soporte —longitudinal específico, longitudinal relacionado, biomecánica o inferencia de producto— y sus límites. No añadas una fuente que no respalde la afirmación específica.

### 10.4 Versionado

Conserva versión de atribución usada al registrar. La vista habitual debe usar un método consistente y mostrar su versión. Si recalculas todo el historial con una versión nueva, debe ser una operación explícita y reversible o una vista alternativa identificada; no alteres silenciosamente gráficos anteriores.

Permite corregir atribuciones de ejercicios personalizados y marcar ajustes del usuario. Una personalización no debe aparecer como regla científica revisada.

### 10.5 Objetivos de series

No impongas diez, veinte o cualquier otro número como requisito universal. El objetivo elegido se almacena por músculo, método de conteo y periodo de vigencia. Un objetivo de series directas no se compara silenciosamente con un total fraccional.

Al iniciar, ofrecer observar primero la rutina habitual o configurar metas. Se puede presentar la referencia general de E01 como contexto, sin asignarla automáticamente a cada subregión ni exigirla a un principiante. Las metas pueden provenir del propietario o de un profesional; anota su procedencia.

Mensajes permitidos: “8 series directas; objetivo elegido: 10”, “2 series por debajo de tu meta configurada”, “hay ejercicios con atribución pendiente”. Mensajes improcedentes: “no crecerás”, “faltan dos series para activar hipertrofia”, “estás sobreentrenado” o “este volumen garantiza crecimiento”.

## 11. Sugerencias de ejercicios y reparto del énfasis

Esta función es central. El propietario quiere elegir libremente y recibir ayuda para que la siguiente sesión cubra zonas menos atendidas, por ejemplo hombro lateral y posterior tras trabajo predominantemente anterior.

### 11.1 Naturaleza de la función

Implementa un motor local, determinista y explicable. No necesita un modelo de lenguaje ni enviar datos fuera del teléfono. Es una ayuda organizativa basada en el registro y en un catálogo de atribuciones; no demuestra que se pueda optimizar el crecimiento exacto de cada cabeza muscular. La variación debe ser organizada y conservar ejercicios de referencia para comparar progreso. [E08]

### 11.2 Entradas

- Grupos previstos para el día.
- Series directas, indirectas y desconocidas en semana calendario y últimos 14 días.
- Fecha de últimas exposiciones y selección de la sesión comparable anterior.
- Metas del usuario cuando existan y su método de conteo.
- Variantes disponibles, favoritos, ejercicios fijados y exclusiones.
- Molestias o restricciones autodeclaradas, sin inferir diagnósticos.
- Preferencias manuales y cobertura cualitativa de regiones.

### 11.3 Reglas de decisión

1. Filtrar por catálogo disponible, grupos del día y exclusiones explícitas.
2. Mantener los ejercicios que el usuario haya fijado como referencias.
3. Si faltan datos, ofrecer una selección inicial editable; no anunciar un déficit muscular.
4. Priorizar una región con menor exposición directa registrada cuando encaje con el día y los ejercicios disponibles.
5. Si hay metas, considerar la distancia a la meta usando el mismo método y vigencia.
6. Usar las series indirectas como contexto, manteniendo su carácter estimado.
7. Evitar proponer varios ejercicios redundantes para la misma región por el solo hecho de pertenecer al mismo grupo.
8. No forzar un ejercicio distinto en cada sesión. Mantener continuidad y ofrecer alternativas.
9. No añadir series por encima del presupuesto elegido de la sesión para “completar todo”. Sugerir una sustitución antes de incrementar trabajo.
10. Si no existe un ejercicio adecuado en el catálogo, indicarlo. No inventar cobertura ni añadir automáticamente un movimiento nuevo.
11. La cercanía temporal de sesiones se muestra como contexto. No diagnosticar recuperación ni bloquear por un umbral genérico de 48/72 horas.
12. Mostrar como máximo pocas sugerencias prioritarias, con “por qué”, “cambiar” y “mantener mi elección”.

El orden lexicográfico de estas reglas es una heurística de producto. Si usas puntuaciones o pesos internos, documenta que son de diseño, no coeficientes obtenidos de estudios. Prueba estabilidad y empates con orden determinista.

### 11.4 Ejemplo obligatorio de comportamiento

Si el lunes se registraron presses y elevaciones frontales, y el viernes sigue sin trabajo directo lateral o posterior en la ventana consultada:

“Tu trabajo reciente de hombro se ha concentrado en la parte anterior. Hoy puedes priorizar elevaciones laterales o peck deck inverso de tu catálogo.”

Mostrar las series y fechas que originan el mensaje. No afirmar que el usuario tiene desbalance anatómico, que está subdesarrollado o que el ejercicio producirá un porcentaje específico de crecimiento.

Si el usuario elige de nuevo el press militar, permitirlo sin castigo. Las sugerencias nunca editan silenciosamente su sesión.

### 11.5 Tiempo desde el último trabajo

Vista de músculo con última exposición directa, última indirecta y horas transcurridas calculadas desde los eventos. Un músculo sin registro dice “sin datos”. Una observación de cansancio no convierte el calendario en una medida fisiológica de recuperación.

No incluir semáforos “recuperado al 100 %”, mediciones inventadas de sistema nervioso, deload obligatorio ni diagnóstico de sobreentrenamiento.

## 12. Gráficos y análisis de entrenamiento

Periodos: semana, mes, tres meses, año, todo e intervalo personalizado si no complica la interfaz. Inicio de semana predeterminado lunes, editable. Diferenciar semana calendario y últimos siete días. Etiquetar periodos incompletos.

### Por ejercicio y variante comparable

- Mayor carga de cada sesión, con repeticiones de la serie que la respalda.
- Récord de repeticiones para una misma carga.
- Historial de todas las series.
- Series de trabajo por sesión y semana.
- Mejor serie bajo un criterio visible, sin comparar solo kilogramos cuando cambian repeticiones.
- Fuerza máxima estimada opcional y secundaria.

La carga máxima de entrenamiento no se llama “1RM real”. La fuerza estimada no debe sustituir el registro original ni invitar a probar máximos.

Si implementas e1RM, como decisión conservadora inicial usa Epley: carga × (1 + repeticiones/30), solo para 2–10 repeticiones, carga externa positiva y series con RIR declarado 0–1; para una repetición real usa la carga observada y etiquétala por separado. Ese filtro es una restricción del producto, no garantía de exactitud. Si RIR es desconocido o no hay ejercicio compatible, no producir el indicador. No aplicar automáticamente a máquinas asistidas, peso corporal ni movimientos cuya convención no se haya definido. Para máquinas elegibles, etiqueta como índice estimado de esa máquina, no fuerza general. La fórmula y su contexto están documentados en E13; sus filtros de presentación son decisiones conservadoras propias y deben identificarse así.

No ajustes e1RM sumando RIR a las repeticiones sin una metodología adicional verificada. Si no puedes respaldar y probar esta función, deja su cálculo fuera de la primera entrega y documenta el alcance; las métricas observadas obligatorias deben seguir completas.

### Por músculo

Series directas, indirectas y fraccionales separables; distribución por día; frecuencia registrada; ejercicios contribuyentes; objetivo configurado; versión de atribución y cobertura desconocida.

Una curva de series por músculo se titula con precisión. No llamarla “crecimiento de bíceps” o “masa muscular ganada”.

### Reglas gráficas

- Ejes y unidades visibles o accesibles.
- No rellenar fechas ausentes con cero en métricas de rendimiento.
- Para series, distinguir cero confirmado, descanso y ausencia de registro.
- Puntos reales; línea entre observaciones solo si se entiende como conexión visual.
- Interpolación que no invente picos; no usar curvas con sobrepasos entre datos.
- Seleccionar un punto abre fecha, valor y series originales.
- Comparaciones contra periodo anterior equivalente; si está incompleto, usar tramo equivalente o identificarlo claramente.
- Si el valor anterior es cero o no existe, no dividir para mostrar un porcentaje infinito.
- Orden cronológico estable al ingresar o editar datos antiguos.
- Cambios de variante o equipo visibles. No mezclar máquinas bajo una línea como si fueran equivalentes.
- Alternativa textual/tabular y compatibilidad con VoiceOver.
- Estados vacíos útiles y pocos puntos visibles sin simulación.

## 13. Récords y doble progresión

Un récord conserva ejercicio, variante, carga, repeticiones, fecha y serie de origen. Excluir calentamientos, intentos y registros eliminados. Si se corrige o borra la serie, recalcular el récord; una celebración no vuelve permanente un error.

Permitir récord de carga y récord de repeticiones a una carga. No generar un récord de fuerza por mayor asistencia. La comparación unilateral usa la misma convención y lado.

Doble progresión desactivable y por ejercicio. El usuario configura rango de repeticiones, número de series de referencia, incremento disponible y criterio de esfuerzo opcional. No inventar sus rangos actuales.

Ejemplo de regla elegida: si completa todas las series de referencia en el extremo superior del rango, bajo condiciones comparables y sin una exclusión manual, sugerir el incremento configurado. Si solo una serie lo alcanza, no sugerir automáticamente como si todas lo hubieran hecho. La sugerencia no cambia los pesos sin aceptación.

La app puede decir “cumpliste tu regla para considerar subir”. No debe ordenar aumentar cada semana ni convertir un entrenamiento más suave en fracaso.

## 14. Asistencia, calendario y cumplimiento

### Registro automático

Crear asistencia al confirmar la primera serie de trabajo elegible de una sesión. Calentamiento aislado o abrir la rutina no bastan. Una sesión parcial con trabajo cuenta como día asistido, pero conserva su estado parcial.

### Registro manual

Permitir “sí fui” sin inventar ejercicios. Diferenciar procedencia manual y automática. Si después se ingresan series, consolidar un solo día, conservando la trazabilidad.

Varias sesiones el mismo día: un día asistido y varias sesiones. Borrar la última serie elegible elimina únicamente la evidencia automática correspondiente; una confirmación manual válida no se borra sin decisión explícita. Prever deshacer para errores.

### Estados del calendario

- Entrenamiento registrado.
- Asistencia manual.
- Descanso planificado.
- Descanso puntual confirmado.
- Planificado sin registro, todavía sin confirmar.
- Ausencia confirmada.
- Futuro.

No mostrar automáticamente una ausencia como hecho por falta de datos. Distinguir día de asistencia y cumplimiento de sesión prevista: una sesión parcial cuenta para asistencia, mientras completar el plan exige su criterio de finalización.

Calendario anual de celdas inspirado en un mapa de contribuciones, adaptado a una pantalla móvil: meses identificados, desplazamiento apropiado, leyenda, detalle al tocar y acceso entre años. No reducir un año entero hasta que resulte ilegible. Añadir vista mensual si mejora la consulta.

El color puede representar asistencia o cantidad de series, pero el modo debe estar identificado. No equiparar más intensidad de color con entrenamiento “mejor”. Usar etiquetas y símbolos además del color.

### Adherencia

Conservar el plan histórico: cambiar hoy los días de rutina no altera el denominador de meses anteriores. Definir métricas separadas: días asistidos, sesiones completadas, días planificados y cumplimiento respecto del plan vigente en cada fecha. Excluir días futuros. Si no hay plan, no calcular un porcentaje de adherencia inventado.

Rachas basadas en oportunidades planificadas o semanas cumplidas; los descansos previstos no las rompen. No felicitar por ignorar descansos ni enviar mensajes de culpa.

## 15. Notificaciones locales y revisión nocturna

Usa UserNotifications y permisos solicitados cuando el usuario habilite avisos. No usar servidor ni APNs para recordatorios definidos en el dispositivo. La app funciona si el permiso se deniega; mostrar el estado real y un acceso a ajustes cuando corresponda. [A01]

### Categorías

1. Recordatorio de entrenamiento, horario independiente por día.
2. Cambio “solo hoy”, sin alterar todos los lunes posteriores.
3. Revisión de asistencia: por defecto 21:00 en días planificados, editable y desactivable.
4. Recordatorio semanal de fotos, desactivado hasta elegir día y hora.
5. Resumen semanal opcional, sin necesidad de enviar datos a un servidor. El aviso programado puede ser una invitación genérica a abrir el resumen; calcular las cifras actualizadas al abrir la app. No prometer generación dinámica garantizada en segundo plano ni mostrar en el aviso cifras antiguas programadas días antes.

### Revisión de asistencia

Mensaje discreto: “¿Cómo fue tu entrenamiento de hoy?” Acciones: “Sí fui”, “Hoy descansé” y “Voy más tarde”.

- Si hay asistencia válida, cancelar la revisión pendiente de esa fecha.
- Si responde sí fui, añadir confirmación manual sin fabricar series.
- Si responde descansé, guardar excepción y evitar insistir esa noche.
- Si elige más tarde, ofrecer 30/60/120 minutos o una hora, sin cruzar de fecha inadvertidamente.
- Si no responde, mantener sin confirmar.
- Si existe una sesión activa o la hora de entrenamiento de hoy es posterior a la revisión, ofrecer mover esa revisión y evitar dos avisos contradictorios.

### Programación correcta

Programar solicitudes identificadas por categoría y fecha. Las revisiones condicionadas a asistencia deben poder cancelarse por fecha; no usar una única repetición semanal que luego reaparezca ese mismo día ya completado.

iOS no ejecuta código arbitrario garantizado cada noche para consultar una condición. Programa anticipadamente fechas concretas, cancela al registrar y reconcilia al abrir la app, cambiar ajustes o recibir una acción. Mantén una ventana futura dentro de los límites reales del sistema y rellénala al usar la app. Define y documenta qué ocurre tras un periodo largo sin abrirla; no prometas programación condicional indefinida si depende de reponer la ventana.

Consulta los límites vigentes de notificaciones pendientes antes de fijar la ventana y prioriza recordatorios elegidos por el usuario. No dependas de una tarea de segundo plano exacta para una función que el sistema no garantiza.

Respetar cambios de zona y horario de verano. Futuros avisos siguen por defecto la hora local elegida; los eventos históricos conservan fecha y zona de origen. Los ajustes Focus, resúmenes y permisos pueden afectar la presentación. No pedir privilegios de alerta crítica para un recordatorio de gimnasio. [A02]

Notificaciones sin fotos, peso corporal, PIN ni información privada innecesaria. Todas las acciones deben ser idempotentes y dirigirse a la fecha del aviso, incluso si se pulsan al día siguiente.

## 16. Fotos privadas y captura guiada

### Poses

Base: frontal relajado, lateral y espalda. Adicionales opcionales: doble bíceps frontal, bíceps de perfil y otras poses personalizadas. Explicar la pose de forma sencilla y ofrecer una ilustración original, neutra y no sexualizada.

El flujo permite una sola pose o varias en una misma revisión. No obligar a completar todas para guardar una foto válida.

### Captura

- Cámara dentro de la app con AVFoundation o alternativa nativa justificada.
- Pedir cámara al abrir esta función, no al instalar. No pedir micrófono para fotografía fija.
- Cuadrícula, referencia de pose y temporizador fotográfico opcional. Este temporizador de cámara sí está permitido; la exclusión de temporizador corresponde al descanso entre series.
- Superposición opcional de una foto anterior de la misma pose, dentro de la bóveda desbloqueada.
- Mantener proporciones, orientación, espejo y encuadre coherentes.
- Confirmar, repetir o cancelar antes de guardar.
- Sugerir condiciones similares de luz y distancia sin convertirlas en requisitos rígidos.
- No aplicar filtros de cuerpo, adelgazamiento, embellecimiento o cambios geométricos que falseen evolución.
- No usar análisis remoto, reconocimiento facial ni IA para clasificar el cuerpo.
- No solicitar ubicación. Eliminar coordenadas GPS y metadatos de captura innecesarios de las copias gestionadas por la app, conservando en su modelo solo fecha, orientación y datos necesarios. No alterar archivos originales ajenos a la app.

Guardar datos de imagen en el contenedor privado de la app; no llamar a la escritura en PhotoKit por defecto. No solicitar acceso completo a la fototeca para una captura interna. Si más adelante se permite importar, usar un selector del sistema con acceso limitado y sin recorrer la biblioteca. Las imágenes originales importadas seguirían perteneciendo a su origen; no prometer ocultarlas o borrarlas automáticamente. [A03]

### Peso y foto

Después de capturar, ofrecer ingresar peso, confirmar que fue medido o marcarlo estimado; se puede omitir. Si se propone el último peso, mostrar su fecha y no crear una medición nueva hasta confirmación expresa.

Al guardar peso desde perfil, ofrecer “Añadir foto” y “Ahora no”. Guardar el peso no requiere cámara ni desbloquear la bóveda, salvo que el usuario elija añadir una imagen.

Una medición de peso puede relacionarse con varias poses del mismo check-in. No crear tres pesajes idénticos por tomar tres fotos. Corregir la medición actualiza su visualización vinculada con trazabilidad.

### Galería y comparación

- Fecha absoluta, tiempo transcurrido, pose y peso asociado con su tipo.
- Filtro por pose y periodo.
- Comparación lado a lado o deslizador entre dos imágenes.
- Secuencia tipo timelapse ordenada por fecha, solo con poses compatibles por defecto.
- Reproducir, pausar, cambiar velocidad y arrastrar el progreso.
- Fecha y peso superpuestos durante reproducción si el usuario los activa.
- Con una sola foto, mostrarla y explicar que la secuencia requiere más registros.
- No modificar proporciones para “alinear” cuerpos. Un ajuste manual de encuadre debe ser reversible y no destruir el original.

No generar un vídeo persistente ni guardar imágenes en Fotos automáticamente. Decodificar progresivamente para no cargar toda la galería a memoria.

## 17. Seguridad de la bóveda y almacenamiento local

### Autenticación

- PIN de cuatro dígitos creado y confirmado por el usuario. Sin PIN predeterminado.
- Face ID opcional mediante LocalAuthentication; texto de permiso claro. [A04]
- No guardar el PIN en texto plano, registros o UserDefaults.
- Usar un verificador derivado con sal aleatoria y una función de derivación apropiada y revisada; no inventar criptografía.
- Limitación de intentos con esperas progresivas, persistente tras reiniciar la app. No borrar fotos automáticamente por equivocarse.
- Face ID cancelado o no disponible permite el flujo de recuperación autorizado, sin desbloquear por error.
- Todas las rutas a fotos —galería, cámara con superposición, comparación, perfil, enlaces internos— pasan por el mismo control.

### Claves y archivos

Usar cifrado autenticado estándar, por ejemplo AES-GCM con una clave aleatoria de 256 bits y nonces únicos gestionados correctamente. Guardar la clave con Keychain, protección apropiada para dispositivo desbloqueado y sin sincronización; revisar `WhenUnlockedThisDeviceOnly` o equivalente vigente. Aplicar protección de archivos completa a imágenes y miniaturas. [A05, A06]

No derivar la única clave de las fotos de un PIN de cuatro dígitos: su espacio de búsqueda es pequeño. El PIN es una barrera de acceso de la app; Keychain, protección del dispositivo y cifrado de archivos aportan la protección de almacenamiento. Documenta el modelo de amenazas real, sin prometer inmunidad en un dispositivo comprometido.

La política de Keychain debe ser coherente con las rutas PIN y Face ID. Si se vincula una clave a autenticación biométrica o del dispositivo, prueba expresamente el acceso por las rutas admitidas. No implementes una combinación que haga imposible abrir con el PIN anunciado.

### Recuperación

“Olvidé el PIN” puede permitir restablecerlo solo después de autenticación del propietario del dispositivo con las APIs del sistema, si la política elegida permite recuperar la clave. Explica esta posibilidad en ajustes. No recuperar con una pregunta fácil ni exponer un botón que resetee el PIN sin autenticación.

Una reinstalación o pérdida del dispositivo no garantiza recuperación de las imágenes locales. Evitar prometerlo por persistencia eventual de un elemento de Keychain.

### Privacidad de la interfaz

Bloquear la bóveda al pasar a segundo plano o bloquear el dispositivo. Al desactivarse la escena, cubrir de inmediato la imagen para que no quede en la captura del selector de aplicaciones. Al volver, autenticar de nuevo según la política. Distinguir una solicitud legítima de autenticación de un desbloqueo accidental durante cambios de escena. [A07]

No crear miniaturas públicas, índices de búsqueda del sistema, previews de archivos ni mensajes de depuración con imágenes o rutas sensibles. Evitar temporales sin cifrar; si una API obliga a usarlos, minimizar duración, protegerlos y limpiarlos también tras errores.

No afirmar que una app iOS puede impedir universalmente capturas de pantalla o fotografías externas. Usar mecanismos públicos de privacidad compatibles cuando proceda, sin trucos no documentados.

### Local significa local

Sin CloudKit, iCloud Drive automático, sincronización, analítica externa ni envío de fotos. Excluir imágenes, miniaturas, metadatos privados y los datos de app que se hayan definido como estrictamente locales de la copia de seguridad automática con los atributos de archivos apropiados; verificar que se reapliquen tras sustituciones y guardados. No guardar el archivo principal en una carpeta sincronizada. [A08]

Mostrar en ajustes una explicación breve: “Tus datos se guardan en este dispositivo. Para conservar una copia independiente puedes exportar un archivo cifrado.” Una segunda carpeta dentro de la misma app no es un respaldo contra pérdida del teléfono.

El borrado debe eliminar original, miniatura, temporales, vínculos e índices derivados. No prometer borrado físico irrecuperable a nivel de memoria flash. Si existe una copia exportada por el usuario, el borrado local no puede eliminarla automáticamente.

## 18. Perfil, peso, IMC y medidas corporales

### Perfil

Campos mínimos: nombre o apodo opcional, fecha de nacimiento, experiencia, altura, peso e intención general de entrenamiento. Género opcional. No exigir sexo, género o etnia para registrar series o calcular la fórmula numérica del IMC.

Todos los datos desconocidos se presentan como tales. Edad derivada de fecha real y fecha de referencia; no fijar “19” como constante.

### Peso

- Historial con fecha de medición editable, unidad y condición medido/estimado.
- Peso actual: medición válida más reciente por fecha, no última fila editada.
- Si el dato más reciente es estimado, indicarlo. Ofrecer vista de tendencia solo con medidos por defecto.
- Si no hay medición reciente, mostrar antigüedad; no llamarlo peso “en tiempo real” medido automáticamente.
- Corregir o borrar el último pesaje devuelve el perfil al registro válido anterior.
- Permitir registro sin foto y foto sin peso.
- Gráfico de puntos y tendencia opcional de siete días solo cuando haya información suficiente, con método y número de observaciones visibles. Como convención de producto, promediar primero los pesajes medidos de cada fecha y después los promedios diarios de los últimos siete días calendario; mostrar tendencia cuando existan al menos tres fechas con medición. Indicar días disponibles sobre siete; no imputar los ausentes ni presentar este promedio como una recomendación fisiológica.

### IMC adulto solicitado

Usar un marco adulto general aplicable desde 18 años, identificado como referencia NHS/NICE; no afirmar que es la clasificación CDC para menores de 20. El NHS admite su calculadora adulta desde 18 años. [B01, B02]

Fórmula: IMC = peso en kg / (altura en metros × altura en metros).

Bandas generales de referencia: <18,5; 18,5 a <25; 25 a <30; ≥30, con las etiquetas estándar traducidas y una presentación contextual y neutral. No convertirlas en una puntuación de fitness ni de ganancia muscular. Calcular categoría sobre valor sin redondear; mostrar normalmente un decimal. Si el redondeo cruza visualmente una frontera y parece contradecir la categoría, mostrar precisión adicional junto a la interpretación para que se entienda el resultado.

La fórmula adulta no cambia por género y no predice crecimiento. Estas bandas generales tampoco son una evaluación individual de riesgo: existen ajustes por población y situaciones clínicas que no se modelan en esta aplicación. Mostrar una nota breve, consultable, sobre esa limitación y la incapacidad del IMC para distinguir músculo y grasa. No prometer personalización por todas las características del perfil.

En el historial usar altura vigente en la fecha del pesaje. Si falta una altura histórica, permitir usar una altura conocida como supuesto identificado; no recalcular silenciosamente el pasado con una altura nueva. Un peso estimado produce un IMC estimado.

No implementar percentiles pediátricos en esta versión personal. Para una futura distribución a menores de 18, definir otra política antes de habilitar interpretaciones; el producto actual no debe extrapolar estas bandas a esa población.

### Medidas corporales

Tipos iniciales opcionales: cintura, pecho, cadera, brazo, muslo y pantorrilla. Lado izquierdo/derecho cuando corresponda. Permitir otras medidas personalizadas.

Cada medida guarda fecha, unidad y protocolo breve: punto de medición y condición relajado/contraído si aplica. Un cambio de protocolo se identifica en el gráfico; no comparar como si fuera idéntico.

Mostrar gráfico por medida, cambio absoluto y periodo comparable. No afirmar que un aumento de perímetro equivale a músculo puro ni que una reducción implica pérdida muscular. No derivar porcentaje de grasa ni metas de peso automáticas.

### Comparaciones externas

Primera versión centrada en comparación con el propio historial. No inventar promedios por edad, género o peso, ni usar datos de competidores como población general. Para habilitar esa función en el futuro se necesitarán fuente, licencia, población, ejercicio, protocolo, muestra y límites verificables. No construir percentiles para máquinas de gimnasio sin una base adecuada.

## 19. Exportación, archivo cifrado y restauración

### Registros de entrenamiento

Exportar CSV con columnas documentadas: IDs, fechas, zona/fecha de entrenamiento, ejercicio, variante, equipo, tipo, estado, carga, unidad, repeticiones, lado y RIR. UTF-8, caracteres españoles correctos y tratamiento seguro de celdas que una hoja de cálculo pudiera interpretar como fórmulas.

Ofrecer JSON versionado para una exportación estructurada completa. No incluir secretos, claves o PIN. Si se exportan mediciones corporales, indicarlo antes y permitir elegir el contenido. Las fotos nunca se incluyen inadvertidamente en una exportación de series.

### Archivo completo opcional

El usuario puede crear un archivo cifrado con datos y, si lo elige, fotografías. Debe requerir desbloquear la bóveda para incluir imágenes. Usar contraseña de exportación suficientemente fuerte, separada del PIN y con confirmación, derivación de clave estándar, sal aleatoria y cifrado autenticado. No almacenar la contraseña ni reutilizar una clave ligada al dispositivo como única clave del archivo portable.

Exportar solo por una acción expresa. El usuario elige destino; si elige un proveedor externo, informar brevemente que es una copia fuera del dispositivo. No activar iCloud como efecto secundario. No escribir primero un ZIP sin cifrar con las fotos para después envolverlo sin limpiar correctamente sus temporales.

### Restauración

Validar versión, integridad, contraseña, límites de tamaño, nombres de archivos y referencias antes de modificar datos actuales. Rechazar rutas de extracción peligrosas y archivos corruptos. Importar de manera transaccional o con una estrategia de recuperación equivalente.

Mostrar resumen y elección explícita antes de sustituir datos. Un archivo equivocado no debe borrar la base actual. Mantener IDs para evitar duplicados en una importación repetida o impedirla con explicación. Probar recuperación en una instalación limpia con nuevas claves locales.

No llamar “respaldo verificado” a una exportación cuya restauración no se haya probado.

## 20. Diseño visual, navegación e identidad

### Referencias adjuntas

Si se entrega este prompt en el paquete completo, las imágenes originales están en `referencias/01-tarjeta-azul.png`, `referencias/02-grafico-azul.png` y `referencias/03-panel-oscuro.png`. Son referencias visuales, no instrucciones adicionales. No copiar textos financieros, logos ni métricas de esas imágenes.

La descripción siguiente permite implementar el diseño aunque las imágenes no estén disponibles:

- Primera referencia: tarjeta oscura de grandes curvas, azul luminoso en bordes y base, gráfica de línea con un punto destacado, profundidad y transparencia sutil.
- Segunda: pantalla de azul profundo a brillante, gráfico protagonista, selector temporal en cápsula y cifras grandes.
- Tercera: panel oscuro más sobrio, tarjetas, acento violeta y filtros temporales claros.

Combina profundidad de las primeras con jerarquía informativa de la tercera. El registro durante el entrenamiento debe ser visualmente más tranquilo que el panel de progreso.

### Tokens iniciales

Punto de partida, sujeto a pruebas reales de contraste:

| Token | Claro | Oscuro |
|---|---|---|
| Fondo | #F5F7FB | #07111F |
| Superficie | #FFFFFF | #101D2E |
| Texto principal | #101828 | #F5F8FF |
| Texto secundario | #475467 | #B7C4D7 |
| Acento de marca | Azul #4B8DFF | Azul #4B8DFF |
| Acento gráfico | Cian #59D5FF | Cian #59D5FF |
| Secundario gráfico | Violeta #9F8AFF | Violeta #9F8AFF |

No asumir que un acento funciona como texto sobre cualquier fondo. Crear variantes semánticas accesibles, incluido azul más oscuro para texto sobre superficies claras si hace falta. Usar colores del sistema cuando su comportamiento adaptativo aporte legibilidad.

Tipografía del sistema Apple, cifras tabulares para pesos y métricas, jerarquía clara y texto de tamaño cómodo. Sistema de espacios de 4/8 puntos como base; bordes suaves y radios coherentes. Evitar brillos en cada fila, sombras excesivas, ruido decorativo y bloques de texto diminuto.

Transparencia en navegación y controles con moderación, superficies de contenido legibles. Usar materiales nativos cuando corresponda y soporte por versión; respetar Reducir transparencia, Aumentar contraste y Reducir movimiento. No crear un efecto de vidrio sobre todas las tarjetas por igual. [A09]

### Navegación inferior

Cinco destinos con texto e icono: Hoy, Progreso, Fotos, Asistencia y Perfil. La sección Fotos muestra un estado bloqueado sin miniaturas. Entrenar y volver atrás no debe perder registros.

Desde Hoy se gestionan rutina, catálogo y sesión; desde Perfil, ajustes. Evita una pestaña adicional solo para configuración.

### Movimiento y respuesta

Microanimación breve al confirmar serie, respuesta háptica configurable, transición suave de gráficos y celebración contenida de récords. No animaciones largas que retrasen la siguiente acción. No mover valores mientras el usuario los está editando.

La reproducción de fotos se inicia por acción del usuario. Respetar reducir movimiento sin eliminar funciones esenciales.

### Logo

Crear un símbolo vectorial original basado en una curva ascendente de extremos redondeados, simple y reconocible en tamaño pequeño y en monocromo. Acompañarlo de “Arco” con tipografía limpia. No usar una mancuerna genérica como único concepto ni detalles que desaparezcan en el icono. Entregar recursos editables y todos los tamaños de app necesarios, con vista clara y oscura cuando el sistema los admita.

Nombre e icono son propuestas de identidad; no declarar disponibilidad de marca ni aprobación comercial.

### Accesibilidad y adaptación

- iPhone 14 como dispositivo prioritario; probar pantalla compacta y tamaño de texto grande.
- Áreas táctiles principales de al menos 44 × 44 puntos. [A10]
- Dynamic Type, VoiceOver, etiquetas de estado, orden lógico y controles numéricos comprensibles.
- Colores acompañados por textos, patrones o símbolos.
- Gráficos accesibles con valores, fechas y resumen textual. [A11]
- Teclado sin tapar confirmar, campos o avisos de error.
- Safe areas, orientación soportada declarada y comportamiento razonable en pantallas mayores.
- Modo oscuro y claro diseñados, sin inversión automática de colores de fotos.
- Contraste suficiente verificado con datos, transparencias y configuraciones de accesibilidad reales.

## 21. Estados vacíos, errores y calidad operativa

Diseña explícitamente: primera sesión, ningún objetivo, ninguna foto, una foto, peso desconocido, RIR omitido, atribución desconocida, ninguna sesión comparable, notificaciones denegadas, cámara denegada, Face ID no disponible, poco almacenamiento y archivo de respaldo corrupto.

Cada estado debe ofrecer una acción útil y conservar el resto de la aplicación funcional. “Sin datos” no se presenta como cero ni fracaso. La información demostrativa solo existe en modo de vista previa o prueba, separado de los datos reales y claramente identificado.

Operaciones de archivo y base de datos coordinadas: una foto no aparece como guardada si falta su archivo; un fallo de cámara no borra el pesaje independiente. Usa escrituras atómicas, referencias verificadas y recuperación de archivos huérfanos. La limpieza no debe eliminar imágenes válidas por un fallo temporal de acceso a archivos protegidos.

No registrar datos corporales ni fotos en logs. Diagnósticos locales sin información sensible y sin telemetría externa. No mostrar detalles técnicos al usuario salvo que ayuden a resolver un error.

Rendimiento: guardado de series sin bloquear la interacción; consultas de gráficos eficientes; miniaturas cifradas y carga progresiva; sin cargar imágenes de años completos en memoria. Verificar con un conjunto sintético equivalente a varios años de entrenamiento y cientos de fotografías, separado del perfil real.

Documentar límites medidos, dispositivo utilizado y tiempo de respuesta observado. No afirmar fluidez o seguridad solo por inspección del código.

## 22. Pruebas y criterios de aceptación

Implementa pruebas significativas sobre reglas, datos y flujos; evita pruebas que solo repitan nombres de vistas. Los servicios del sistema deben poder simularse, complementando con pruebas reales donde el simulador no basta.

| ID | Escenario y resultado obligatorio |
|---|---|
| T01 | Abrir rutina precargada: cero series realizadas hasta confirmación. |
| T02 | Confirmar una fila válida: se guarda una sola serie; repetir callback no duplica. |
| T03 | Cerrar inmediatamente después de guardar y reabrir: sesión y serie persisten. |
| T04 | Fallo de escritura: se conserva borrador, no aparece guardado falso y reintentar no duplica. |
| T05 | Editar o eliminar una serie pasada: gráficos, récords y conteos se recalculan. |
| T06 | Cambiar plantilla: el entrenamiento histórico mantiene su selección y valores originales. |
| T07 | Calentamiento: visible en historial y excluido del conteo de trabajo y asistencia automática. |
| T08 | RIR vacío: serie válida, sin inferir RIR ni descartar trabajo. |
| T09 | Dos series directas y cuatro indirectas para un músculo: D=2, I=4, F=4. |
| T10 | Una serie clasificada directa e indirecta por error: validación lo rechaza o resuelve un único papel. |
| T11 | Una serie que alcanza dos regiones de hombro: agregado hombros usa unión/máximo, no suma duplicada. |
| T12 | Tres pares unilaterales: tres exposiciones por lado; no seis para el mismo músculo general. |
| T13 | Solo un lado: el otro permanece sin realizar. |
| T14 | Pulldown de brazos extendidos: no suma bíceps por un mapeo genérico de espalda. |
| T15 | Prensa sentada: no suma isquiotibiales automáticamente. |
| T16 | Agarre isométrico: no genera series directas de antebrazo en cada ejercicio. |
| T17 | Variante con atribución desconocida: aparece pendiente y no crea crédito exacto inventado. |
| T18 | Cambiar versión de atribución: se informa y conserva coherencia del historial. |
| T19 | Lunes de hombro anterior sin trabajo lateral/posterior: sugerencia del viernes explica los datos y ofrece catálogo pertinente. |
| T20 | Catálogo sin ejercicio apto: informa falta de opción, sin inventarla. |
| T21 | Usuario rechaza sugerencia: conserva elección y no recibe penalización. |
| T22 | Sin historial: no diagnostica déficit ni fatiga. |
| T23 | Convertir 100 lb: 45,359237 kg internamente; ida y vuelta sin deriva acumulativa. |
| T24 | Mancuernas por unidad: récord mantiene convención; no duplica kilos mostrados. |
| T25 | Máquinas distintas: historial comparable separado o cambio explícito identificado. |
| T26 | Mayor asistencia: no se celebra como mayor fuerza. |
| T27 | 40 kg × 8 y luego 40 kg × 10: identifica progreso de repeticiones. |
| T28 | Mayor carga con menos repeticiones: muestra ambas variables, sin proclamar superioridad absoluta no definida. |
| T29 | Borrar serie que daba récord: récord recalculado y celebración no preserva error. |
| T30 | Solo una serie alcanza techo de doble progresión: no considera satisfechas todas las series. |
| T31 | Carga anterior cero o ausente: comparación porcentual sin división inválida. |
| T32 | Fecha sin datos en gráfico de carga: no se dibuja como cero. |
| T33 | Semana en curso: se identifica parcial y no se compara engañosamente con una completa. |
| T34 | Primera serie de trabajo: crea asistencia automática; abrir rutina no. |
| T35 | Dos sesiones y asistencia manual mismo día: un día asistido, sin triplicar. |
| T36 | Sesión parcial: asistencia válida, estado parcial conservado. |
| T37 | Borrar última serie: se revisa evidencia automática y conserva confirmación manual independiente. |
| T38 | Descanso jueves/domingo: no rompe racha basada en el plan ni dispara revisión nocturna estándar. |
| T39 | Cambiar plan actual: no altera denominador de adherencia histórica. |
| T40 | Notificaciones denegadas: app funciona y muestra estado verdadero. |
| T41 | Asistencia antes de 21:00: cancela aviso de revisión de esa fecha, sin cancelar semanas futuras. |
| T42 | Aviso respondido al día siguiente: acción corresponde a la fecha original. |
| T43 | Posponer varias veces: sin solicitudes duplicadas ni cruce de fecha inadvertido. |
| T44 | Entrenamiento posterior a revisión o sesión activa: no aparecen avisos contradictorios. |
| T45 | Año bisiesto, cambio de año, semana y zona: fechas, celdas y agregaciones correctas. |
| T46 | Sesión cruza medianoche: conserva fecha de entrenamiento y horas reales. |
| T47 | Cámara denegada o captura cancelada: resto de la app y pesaje permanecen utilizables. |
| T48 | Capturar foto: existe archivo privado y no se escribe en fototeca ni álbum Ocultos. |
| T49 | Tres poses con un pesaje: una medición vinculada, no tres registros duplicados. |
| T50 | Foto sin peso y peso sin foto: ambos flujos válidos. |
| T51 | Peso sugerido antiguo sin confirmar: no crea una medición nueva. |
| T52 | Registrar hoy una foto/peso antiguo: perfil conserva el peso de fecha más reciente. |
| T53 | Último peso estimado: etiqueta visible; tendencia predeterminada de medidos lo distingue. |
| T54 | Borrar último pesaje: perfil vuelve al anterior válido y actualiza gráficos. |
| T55 | 70 kg y 1,70 m: IMC interno aproximado 24,22145; mostrado 24,2. |
| T56 | Fronteras 18,5/25/30: clasificación por valor sin redondear; 24,96 no pasa a 25 por mostrar un decimal. |
| T57 | Edad 19: referencia adulta 18+ identificada; no se afirma usar bandas CDC para esa edad. |
| T58 | Cambio de altura: IMC histórico conserva altura vigente o muestra supuesto explícito. |
| T59 | Medidas izquierda/derecha y protocolos distintos: gráficas no los mezclan silenciosamente. |
| T60 | PIN incorrecto, reinicio y manipulación simple de reloj: limitación de intentos coherente, sin acceso accidental. |
| T61 | Face ID cancelado, denegado o sin configurar: bóveda permanece bloqueada. |
| T62 | Ruta a comparación/superposición desde perfil o enlace: mismo requisito de autenticación. |
| T63 | Salir de app mostrando foto: selector de apps no expone imagen. |
| T64 | Olvidé PIN: requiere autenticación del sistema; no basta pulsar restablecer. |
| T65 | Fotos y miniaturas no son imágenes legibles almacenadas fuera de la protección definida; no hay claves en exportación o logs. |
| T66 | Atributos de exclusión de backup y protección reaplicados después de guardar/reemplazar archivos. |
| T67 | Borrar foto: elimina derivados y asociaciones según reglas; no deja miniatura pública. |
| T68 | Secuencia temporal: orden cronológico, filtro por pose y memoria controlada. |
| T69 | CSV con tildes, comillas y nombres peligrosos de hoja de cálculo: exportación correcta y segura. |
| T70 | Archivo cifrado: contraseña incorrecta o corrupción no modifica datos actuales. |
| T71 | Restauración en instalación limpia: recupera datos e imágenes con nuevas claves locales y relaciones válidas. |
| T72 | Reimportación: no duplica silenciosamente registros. |
| T73 | Migración desde esquema anterior: conserva datos; fallo no provoca borrado automático. |
| T74 | Modo claro, oscuro, texto grande, VoiceOver y reducir transparencia/movimiento: acciones esenciales accesibles. |
| T75 | Sin conexión: registro, gráficos, fotos y recordatorios locales configurados siguen funcionando. |
| T76 | Primera apertura real: ningún dato de demostración aparece como entrenamiento del propietario. |

Pruebas reales prioritarias en iPhone: captura, Face ID, transición a segundo plano, persistencia al cerrar, notificaciones y rendimiento de galería. Señala cuáles solo se probaron con dobles o simulador.

## 23. Etapas de implementación, entregables y definición de terminado

### Etapa A — Base verificable

Inspección, proyecto nativo, entidades, persistencia, unidades, catálogo, plantillas y navegación. Crear decisiones técnicas breves y matriz requisito → implementación → prueba.

### Etapa B — Entrenamiento completo

Sesión rápida, confirmación, recuperación, variantes, unilateralidad, edición histórica y asistencia automática. Verificar que registrar series ya sea cómodo antes de ampliar paneles.

### Etapa C — Cálculos y sugerencias

Conteos versionados, fuentes, mapa muscular, metas configurables, gráficos, récords, doble progresión y selección explicable. Pruebas con ejemplos conocidos y atribuciones desconocidas.

### Etapa D — Perfil, calendario y avisos

Pesajes, altura, IMC, medidas, gráficos corporales, historial de plan, calendario anual y programación local de recordatorios.

### Etapa E — Bóveda completa

PIN, Face ID, claves, captura, poses, comparación, secuencia temporal, privacidad de escenas, borrado y archivo cifrado con restauración real.

### Etapa F — Diseño y validación integral

Temas, icono, accesibilidad, animaciones, estados vacíos, errores, rendimiento y pruebas en dispositivo cuando esté disponible. El diseño debe acompañar las etapas anteriores, no sustituir funcionalidad al final.

### Entregar

- Proyecto Xcode instalable y fuentes completas.
- Recursos originales de icono e ilustraciones.
- README con entorno real usado, compilación, instalación en iPhone y limitaciones de firma.
- Decisiones de arquitectura y política de almacenamiento/recuperación.
- Registro de fuentes y atribuciones musculares con su versión.
- Matriz de requisitos y pruebas; comandos de verificación ejecutados y resultados.
- Guía breve de uso, respaldo y recuperación.
- Lista concreta de funciones pendientes o no verificadas, si existe, sin ocultarlas detrás de la palabra “terminado”.

No dar por completado el trabajo hasta que el flujo real permita: configurar el perfil; elegir la rutina; registrar, cerrar y recuperar una sesión; ver sus gráficos y conteos; consultar asistencia; configurar avisos; guardar un pesaje o medida; tomar una foto privada; autenticar acceso; comparar fotos y restaurar un archivo exportado.

Si el entorno carece de firma o iPhone conectado, completa lo verificable y proporciona el paso manual exacto que queda. No afirmes instalación, Face ID real o avisos entregados sin haberlos probado.

## 24. Fuentes verificables y qué respaldan

Estas fuentes se consultaron para preparar el encargo. Verifica sus contenidos antes de traducir una conclusión en una regla. Si solo puedes acceder al resumen, indícalo y no atribuyas resultados detallados del texto completo. Una fuente relacionada no valida todos los valores de la matriz.

### Evidencia de entrenamiento

- **E01 — ACSM, 2026.** *Resistance Training Prescription for Muscle Function, Hypertrophy, and Physical Performance in Healthy Adults: An Overview of Reviews.* Síntesis para adultos sanos; orienta volumen, esfuerzo e individualización. No determina una dosis óptima universal ni una fórmula de recuperación. [Artículo](https://pubmed.ncbi.nlm.nih.gov/41843416/) · [Texto completo](https://pmc.ncbi.nlm.nih.gov/articles/PMC12965823/) · [Comunicación oficial](https://acsm.org/resistance-training-guidelines-update-2026/).
- **E02 — Pelland y colaboradores, 2026; publicación electrónica 2025.** *The Resistance Training Dose Response: Meta-Regressions Exploring the Effects of Weekly Volume and Frequency on Muscle Hypertrophy and Strength Gains.* Justifica distinguir series directas/indirectas y estudiar un modelo fraccional. No valida media serie para todos los sinergistas ni todas las variantes. DOI 10.1007/s40279-025-02344-w. [PubMed](https://pubmed.ncbi.nlm.nih.gov/41343037/).
- **E03 — Robinson y colaboradores, 2024.** *Exploring the Dose–Response Relationship Between Estimated Resistance Training Proximity to Failure, Strength Gain, and Muscle Hypertrophy.* Relación exploratoria con RIR; útil para contexto, con incertidumbre y sin obligación de fallo. DOI 10.1007/s40279-024-02069-2. [Artículo](https://link.springer.com/article/10.1007/s40279-024-02069-2).
- **E04 — Refalo y colaboradores, 2023; publicación electrónica 2022.** *Influence of Resistance Training Proximity-to-Failure on Skeletal Muscle Hypertrophy.* Diferencia fallo momentáneo de otras definiciones y no demuestra superioridad general del fallo. [PubMed](https://pubmed.ncbi.nlm.nih.gov/36334240/).
- **E05 — Vigotsky y colaboradores, 2018.** *Methods matter: the relationship between strength and hypertrophy depends on methods of measurement and analysis.* Respalda distinguir rendimiento y medición de hipertrofia. [PubMed](https://pubmed.ncbi.nlm.nih.gov/29967737/).
- **E06 — Schoenfeld y colaboradores, 2019.** *Calculating Set-Volume for the Limb Muscles with the Performance of Multi-Joint Exercises.* Analiza límites biomecánicos y empíricos del conteo entre ejercicios multiarticulares y monoarticulares. Es una perspectiva, no una tabla universal de coeficientes. [PubMed](https://pubmed.ncbi.nlm.nih.gov/31336594/) · [Texto](https://pmc.ncbi.nlm.nih.gov/articles/PMC6681288/).
- **E07 — Vigotsky y colaboradores, 2018.** *Interpreting Signal Amplitudes in Surface Electromyography Studies in Sport and Rehabilitation Sciences.* Evitar inferir crecimiento muscular directamente de amplitudes EMG. [Texto](https://pmc.ncbi.nlm.nih.gov/articles/PMC5758546/).
- **E08 — Kassiano y colaboradores, 2022.** *Does Varying Resistance Exercises Promote Superior Muscle Hypertrophy and Strength Gains? A Systematic Review.* Sustenta variación organizada y límites de rotación excesiva; no prescribe un algoritmo individual. DOI 10.1519/JSC.0000000000004258. [PubMed](https://pubmed.ncbi.nlm.nih.gov/35438660/).
- **E09 — Kinoshita y colaboradores, 2026.** *Hypertrophic Effects of Single- versus Multi-Joint Exercise: A Direct Comparison between Knee Extension and Leg Press.* Diferencias entre músculos y regiones; no transferir un protocolo de prensa a toda máquina y ejecución. DOI 10.1249/MSS.0000000000003957. [PubMed](https://pubmed.ncbi.nlm.nih.gov/41630124/).
- **E10 — Maeo y colaboradores, 2023; publicación electrónica 2022.** *Triceps brachii hypertrophy is substantially greater after elbow extension training performed in the overhead versus neutral arm position.* Ejemplo de especificidad regional; no prueba equivalencia con todo skull crusher ni permite multiplicar su conteo. [PubMed](https://pubmed.ncbi.nlm.nih.gov/35819335/).
- **E11 — Kinoshita y colaboradores, 2023.** *Triceps surae muscle hypertrophy is greater after standing versus seated calf-raise training.* Diferencias según posición de rodilla y músculo; contexto para variantes, no coeficientes generales. [PubMed](https://pubmed.ncbi.nlm.nih.gov/38156065/).
- **E12 — IUSCA, 2021.** *Resistance Training Recommendations to Maximize Muscle Hypertrophy in an Athletic Population.* Consenso complementario de programación, con población y fecha identificadas. DOI 10.47206/ijsc.v1i1.81. [Artículo](https://journal.iusca.org/index.php/Journal/article/view/81).
- **E13 — Royal College of Physicians, NRAP, 2025.** Documento oficial de preguntas frecuentes que presenta la fórmula de Epley como estimación a partir de una carga y repeticiones al fallo. Se cita para verificar la fórmula, no como validación de exactitud para todos los ejercicios, poblaciones o series con RIR. [Documento](https://www.rcp.ac.uk/media/j1llw4ul/pr_faqs_v51_aug_2025.pdf).

### IMC y contexto corporal

- **B01 — NHS.** Calculadora adulta desde 18 años, fórmula y límites por masa muscular. [Referencia](https://www.nhs.uk/health-assessment-tools/calculate-your-body-mass-index/calculate-bmi-for-adults).
- **B02 — NICE NG246.** Referencias de IMC y límites de evaluación; no implementar una valoración clínica completa ni ajustes étnicos inventados. [Guía](https://www.nice.org.uk/guidance/ng246/chapter/Identifying-and-assessing-overweight-obesity-and-central-adiposity).
- **B03 — CDC.** Su marco adulto comienza a los 20; se incluye para documentar por qué esta app utiliza el marco NHS 18+ solicitado y no etiqueta su interpretación como CDC. [Referencia](https://www.cdc.gov/bmi/adult-calculator/).

### Documentación de Apple

- **A01:** [Programar y cancelar notificaciones locales](https://developer.apple.com/documentation/UserNotifications/scheduling-a-notification-locally-from-your-app).
- **A02:** [Notificaciones, Focus y entrega](https://developer.apple.com/design/human-interface-guidelines/managing-notifications).
- **A03:** [Datos de captura y guardado en fototeca como operación explícita](https://developer.apple.com/documentation/avfoundation/saving-captured-photos) · [Permisos de cámara](https://developer.apple.com/documentation/avfoundation/requesting-authorization-to-capture-and-save-media).
- **A04:** [LocalAuthentication](https://developer.apple.com/documentation/localauthentication).
- **A05:** [Protección de Keychain](https://support.apple.com/guide/security/keychain-data-protection-secb0694df1a/web).
- **A06:** [Protección de archivos](https://developer.apple.com/documentation/foundation/fileprotectiontype).
- **A07:** [Privacidad y captura de interfaz al pasar a segundo plano](https://developer.apple.com/documentation/uikit/preparing-your-ui-to-run-in-the-background).
- **A08:** [Datos y exclusión de copias automáticas](https://developer.apple.com/documentation/foundation/optimizing-your-app-s-data-for-icloud-backup).
- **A09:** [Materiales y Liquid Glass](https://developer.apple.com/design/human-interface-guidelines/materials).
- **A10:** [Controles táctiles y legibilidad](https://developer.apple.com/design/tips/).
- **A11:** [Gráficos accesibles](https://developer.apple.com/design/human-interface-guidelines/charts).
- **A12:** [Instalación personal y límites de firma](https://developer.apple.com/help/account/basics/about-your-developer-account).
- **A13:** [Qué significa el álbum Ocultos de Apple Fotos](https://support.apple.com/en-au/104987).

## 25. Comprobación final antes de entregar

Relee el documento completo y verifica específicamente:

- No introdujiste temporizador de descanso.
- La máquina de pierna es una prensa sentada con asiento móvil.
- Los fondos son empuje sentado en máquina, no fondos asistidos.
- Los presses libres confirmados son con barra.
- El pulldown de brazos extendidos no se confunde con jalón con flexión de codo.
- El catálogo es flexible y las sugerencias se explican con registros reales.
- No afirmas coeficientes musculares exactos garantizados.
- Las fotos quedan en una bóveda local, fuera de Apple Fotos y sin sincronización automática.
- Face ID y PIN protegen todas las rutas privadas.
- Peso y foto se pueden registrar por separado.
- IMC adulto utiliza referencia 18+ identificada, con límites y sin diagnóstico.
- Datos desconocidos se configuran en la app; no hay información corporal inventada.
- No existen promedios externos ficticios, crecimiento muscular calculado desde kilos o recuperación exacta.
- El flujo principal funciona sin conexión y después de cerrar/reabrir.
- Pruebas y documentación reflejan lo realmente verificado.

Empieza inspeccionando el entorno, registra tus decisiones iniciales y procede con la implementación completa siguiendo estas prioridades.
