# Arco — Auditoría de seguridad del repositorio público

Repositorio: `github.com/isaias-J/arco` (público). Fecha: 2026-11-02.

## Qué se publicó en el primer push (commit `0888e4d`, ya sustituido)
184 archivos: código de la app y de ArcoCore, pruebas, proyecto Xcode, documentación,
especificación, las skills de `.kiro/skills` y tres imágenes de referencia.

## Análisis realizado sobre el contenido publicado
| Comprobación | Resultado |
|---|---|
| Claves de API, tokens, claves privadas, certificados, perfiles de firma | Ninguno |
| Bases de datos, copias `.arcobk`, informes de fallos, artefactos de compilación | Ninguno (excluidos por `.gitignore`) |
| Equipo de firma (`DEVELOPMENT_TEAM`) o identidad de firma | Ninguno |
| Rutas locales del Mac (`/Users/...`) | Ninguna |
| Contraseñas | Solo contraseñas ficticias dentro de las pruebas automáticas (no protegen nada) |
| Red / envío de datos desde la app | Ninguno: no hay URLSession, sockets ni servicios externos |
| Registros con datos sensibles (`print`, `NSLog`, `os_log`) | Ninguno |
| Metadatos de imágenes (GPS, dispositivo) | Ninguno; las capturas solo incluían "Screenshot" y dimensiones |
| Scripts de las skills | Solo invocan `xctrace` localmente (herramienta de Apple); sin red ni ejecución remota |

## Problemas encontrados y corregidos
1. **Datos de prueba con aspecto de datos personales.** Una prueba usaba un nombre real y
   una fecha de nacimiento inventada (2007-03-01) que podía confundirse con la real. Se
   sustituyeron por "Persona de prueba" y 2000-01-01.
2. **Imágenes de referencia de terceros.** Las tres capturas de diseños ajenos no deben
   redistribuirse en un repositorio público (derechos de autor). Se retiraron del repositorio
   y se ignoran (`ARCO_PAQUETE_PARA_CLAUDE/referencias/`); siguen en tu Mac.
3. Se reescribió el único commit y se publicó con `--force-with-lease` (`0888e4d` → `6ef840d`).
   Comprobado: la imagen devuelve 404 en `main` y la API de GitHub ya no sirve el commit
   anterior por su identificador (HTTP 422).

## Puntos que decides tú (no son secretos, pero son públicos)
- **Correo del autor de los commits** (`git config user.email`): aparece en cada commit
  público. Si prefieres ocultarlo, configura el correo `noreply` de GitHub
  (GitHub → Settings → Emails) antes de los próximos commits. No modifiqué tu configuración.
- **La especificación** (`ARCO_PROMPT_MAESTRO.md`) describe tu edad aproximada, tu teléfono y
  tu rutina semanal. No es información de acceso, pero es personal. Si no quieres que sea
  pública, indícalo y la retiro del repositorio del mismo modo.
- GitHub puede conservar en caché objetos antiguos durante un tiempo. Como no se publicó ningún
  secreto, no hace falta rotar credenciales.

## Protección para los siguientes push
`scripts/preflight-publico.sh` analiza lo que se va a subir (artefactos, secretos, rutas
locales, contraseñas literales fuera de pruebas, registros sensibles) y falla si encuentra algo.
Se ejecuta antes de cada push.

## Seguridad de la app (revisión de código)
- Fotos: AES-GCM con clave aleatoria de 256 bits en Keychain (`WhenUnlockedThisDeviceOnly`, no
  sincronizable), archivos con protección completa y excluidos de la copia automática.
- PIN: verificador PBKDF2-HMAC-SHA256 (210 000 iteraciones) con sal aleatoria en Keychain;
  límite de intentos persistente; nunca en UserDefaults ni en registros.
- Copia portable: contraseña propia (≥ 8 caracteres), PBKDF2 + AES-GCM por fragmento con datos
  autenticados (índice, total y resumen de cabecera); los nombres de archivo restaurados los
  genera la app (no se usan rutas del archivo: sin recorrido de directorios).
- Corregido: posible pérdida de una foto si dos operaciones creaban la clave de la bóveda a la
  vez (ahora se relee la clave almacenada).
