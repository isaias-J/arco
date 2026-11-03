# Arco — Verificaciones que solo se pueden hacer en el iPhone

Todo lo demás está probado con pruebas automáticas o en el simulador aislado (ver `03-PRUEBAS.md`).
Estas comprobaciones dependen de cámara, Face ID, código del dispositivo, entrega real de avisos,
app Archivos, rendimiento o accesibilidad del hardware.

Cómo anotar: al terminar cada punto, cambia su fila en `03-PRUEBAS.md` a "probado en iPhone real"
o anota lo que viste distinto. Si algo falla, una captura de pantalla y la hora ayudan a localizarlo.

## 0. Instalar (requiere tu Apple ID; solo tú puedes hacerlo)
1. Abre `Arco.xcodeproj` en Xcode → target **Arco** → **Signing & Capabilities** → **Team**: tu Apple ID.
   Si Xcode dice que el identificador ya existe, cambia `com.arco.app` por, p. ej., `com.<tunombre>.arco`.
2. Conecta el iPhone por cable, desbloquéalo, acepta "Confiar en este ordenador" y actívalo en
   Ajustes → Privacidad y seguridad → **Modo de desarrollador** (pide reiniciar).
3. Selecciona el iPhone como destino y pulsa **Run** (⌘R).
4. Si el iPhone dice "Desarrollador no fiable": Ajustes → General → VPN y gestión de dispositivos → tu cuenta → Confiar.
- **Esperado:** Arco abre en la pantalla "Configuración", sin datos de ejemplo.
- Con cuenta gratuita la instalación caduca a los 7 días; volver a pulsar Run la renueva sin borrar datos.

## 1. Configuración y uso diario básico (5 min)
1. Rellena lo que quieras, activa "Indicar cuándo empezaste a entrenar" y elige tu fecha real. Pulsa **Empezar**.
2. En Hoy, **Empezar entrenamiento** → elige un ejercicio → **Empezar** → escribe peso y reps → ✓.
3. Cierra la app desde el selector de apps (deslizar hacia arriba) y vuelve a abrirla.
- **Esperado:** la serie sigue confirmada y la sesión se puede reanudar. Asistencia → hoy aparece como entrenamiento registrado.
  Perfil → Datos personales muestra tu fecha de inicio y "Tiempo entrenando".

## 2. Cámara y fotos privadas (T47–T51, T67)
1. Fotos → **Crear PIN de la bóveda** (4 dígitos) → **Tomar fotos**.
2. Primera vez: iOS pide permiso de cámara. Pulsa **No permitir**.
   - **Esperado:** Arco explica que necesita la cámara y ofrece **Abrir Ajustes**; no se bloquea ni pierde nada.
3. Ajustes → Arco → Cámara: activar. Vuelve a **Tomar fotos**.
4. Haz la pose frontal relajada, después lateral, con el temporizador si quieres.
- **Esperado:** arriba a la izquierda de la vista previa ves la silueta de la pose y sus pasos;
  "Menos" la reduce y "Cómo colocarte" la amplía. La silueta y la cuadrícula **no** aparecen en la
  foto guardada. En una segunda revisión, "superponer la foto anterior" sigue funcionando.
5. Al terminar, elige **Vincular último peso** o escribe un peso y **Guardar peso**.
- **Esperado:** las poses quedan con un solo pesaje vinculado (no uno por foto).
6. Abre la app **Fotos** de Apple y busca en Recientes y en Ocultos.
- **Esperado:** las fotos de Arco **no aparecen** en ningún álbum.
7. En Arco, abre una foto → **Eliminar foto** → confirmar.
- **Esperado:** desaparece de la cuadrícula, de Comparar y de Secuencia; el pesaje se conserva.
8. Con 2 fotos de la misma pose en fechas distintas: **Comparar** y **Secuencia**.
- **Esperado:** se ven lado a lado y en secuencia; ningún vídeo se crea ni se guarda.

## 3. Face ID y PIN (T60–T64)
1. Perfil → Bóveda de fotos: activa Face ID. Bloquea el iPhone y vuelve a Fotos → **Usar Face ID**.
- **Esperado:** se abre con tu cara.
2. Repite y cancela el diálogo de Face ID.
- **Esperado:** la bóveda sigue cerrada; se puede usar el PIN.
3. Escribe un PIN incorrecto 4 o 5 veces seguidas.
- **Esperado:** desde el tercer fallo aparece "Espera N segundos" (5 s, luego 15 s, 30 s…) y el botón
  Desbloquear se desactiva durante la espera. Las fotos no se borran.
4. **Olvidé mi PIN** → Continuar → iOS pide Face ID o el código del iPhone → crea un PIN nuevo.
- **Esperado:** las fotos siguen ahí con el PIN nuevo.
5. Con una foto abierta, desliza para ver el selector de apps.
- **Esperado:** la miniatura de Arco no muestra la foto (pantalla de privacidad). Al volver, la bóveda pide desbloqueo.

## 4. Avisos locales (T40–T44, resumen semanal)
1. Perfil → Recordatorios → **Permitir avisos** → Permitir.
2. En "Revisión de asistencia", pon la hora de hoy a 2–3 minutos vista. Bloquea el iPhone.
- **Esperado:** llega "¿Cómo fue tu entrenamiento de hoy?". Mantén pulsado el aviso:
  - **Sí fui** → Asistencia muestra hoy como asistencia manual.
  - (Otro día) **Hoy descansé** → hoy como descanso confirmado.
  - (Otro día) **Voy más tarde** → abre Arco con 30 / 60 / 120 minutos; elige 30 → el aviso vuelve a los 30 min y no se duplica.
3. Pon de nuevo la revisión a pocos minutos y antes de que llegue registra una serie de trabajo.
- **Esperado:** ese día la revisión **no llega**.
4. En un día de descanso planificado (jueves o domingo con la rutina inicial).
- **Esperado:** no llega revisión ese día.
5. Activa "Resumen semanal" y elige un día/hora cercanos.
- **Esperado:** aviso genérico; al abrirlo, las cifras de Progreso → Resumen semanal coinciden con tus registros.
6. Ajustes del iPhone → Notificaciones → Arco → desactivar. Vuelve a Recordatorios.
- **Esperado:** el estado dice desactivado y ofrece **Abrir Ajustes del sistema**; el resto de la app funciona.

## 5. Copia cifrada y reinstalación (T65, T70–T72)
Hazlo primero con datos ficticios. No borres la app con datos reales hasta comprobar que la copia
se abre y muestra lo esperado en la previsión; guarda la copia fuera del iPhone (Mac o nube) además.
1. Antes de exportar, en Catálogo renombra un ejercicio (p. ej. "Curl martillo" → "Martillo prueba")
   y archiva otro. Desbloquea la bóveda. Perfil → Copia de seguridad → contraseña de 8+ caracteres →
   activa **Incluir fotos** → **Crear copia cifrada** → guarda en Archivos (En mi iPhone).
- **Esperado:** la pantalla dice "Fotos: sí" y el archivo `Arco-<fecha>.arcobk` aparece en Archivos.
2. Prueba restaurar con una contraseña **incorrecta**.
- **Esperado:** "Contraseña incorrecta. No se modificó ningún dato."
3. Restaura con la contraseña correcta **sin borrar nada**.
- **Esperado:** la previsión dice "Ya están aquí sin cambios: N registros" y no promete añadir nada.
  Elige **Reemplazar con la copia** → **Reemplazar**: aparece una segunda confirmación que dice qué
  se eliminaría. Pulsa **Cancelar**, vuelve a **Combinar (recomendado)** → **Restaurar**.
  El mensaje empieza por "Restauración terminada." y dice "No había registros nuevos".
4. Empieza un entrenamiento nuevo, escribe un peso y unas repeticiones en un borrador **sin
   confirmarlo**, y restaura otra vez la misma copia.
- **Esperado:** con **Combinar**, la previsión no anuncia eliminaciones y dice que esa sesión y
  su borrador "solo están en este iPhone y se conservan"; tras restaurar, el entrenamiento sigue
  abierto con el borrador intacto. Con **Reemplazar** (cancela en la confirmación), la previsión
  muestra en rojo "Se ELIMINARÁN… 1 sesiones, 1 borradores sin realizar".
5. Crea un ejercicio personalizado nuevo y elige **Reemplazar** en la previsión (cancela después).
- **Esperado:** dice "Se conserva 1 ejercicio del catálogo que la copia no tiene: <nombre>
  (personalizado, sin sesiones)…"; no lo presenta como eliminado.
6. Borra Arco del iPhone (mantener pulsado el icono → Eliminar app). Vuelve a instalar con Run.
7. En Configuración, **Restaurar desde una copia de Arco** → elige el archivo → contraseña correcta →
   **Restaurar**.
- **Esperado:** vuelven sesiones, series, pesos, asistencia, rutina, ejercicios personalizados y fotos;
  el ejercicio renombrado conserva su nombre y el archivado sigue archivado. Las fotos se abren tras
  crear un PIN nuevo. Restaurar el mismo archivo otra vez no duplica nada.

## 5b. Gráficas nuevas
1. Progreso → **Series por músculo en el tiempo**: elige un grupo, cambia Semanas/Meses/Años y el método.
- **Esperado:** la semana o el mes en curso aparecen atenuados como "incompleto"; las semanas en las que
  no registraste nada salen como raya y "sin registros", no como cero.
2. Progreso → un ejercicio → **Repeticiones por sesión**.
- **Esperado:** el selector "Misma carga: X" muestra la mejor serie de cada sesión con esa carga; "Serie
  más pesada" avisa de que la carga cambia y la tabla indica la carga de cada punto.

## 6. Sin conexión (T75)
1. Activa Modo avión. Usa Arco: registra series, mira Progreso, abre la bóveda, crea una copia.
- **Esperado:** todo funciona. Solo los enlaces de "Fuentes y método" no abren (necesitan internet).

## 7. Accesibilidad (T74)
1. Ajustes → Accesibilidad → VoiceOver activado. Recorre Hoy y registra una serie.
- **Esperado:** cada botón se anuncia con nombre claro (p. ej. "Confirmar serie 1");
  el calendario anuncia el estado de cada día, no solo un color.
2. Texto más grande al máximo, Reducir movimiento y Reducir transparencia.
- **Esperado:** nada se corta ni se superpone de forma que impida registrar una serie.

## 8. Rendimiento y almacenamiento (T66, T68)
1. Tras varias semanas (o muchas fotos), abre Fotos → Secuencia y desplázate por la cuadrícula.
- **Esperado:** fluido; si hay tirones, anótalo con el número de fotos.
2. Exporta una copia con muchas fotos.
- **Esperado:** puede tardar y la pantalla queda ocupada mientras tanto (limitación conocida), pero termina sin error.
3. Ajustes → General → Almacenamiento del iPhone → Arco.
- **Esperado:** tamaño razonable; la base de datos está excluida de la copia de iCloud (no visible desde aquí;
  se comprueba en la prueba automática `storeExcludedFromBackup`).
