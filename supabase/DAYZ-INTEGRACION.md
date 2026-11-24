# Integración Atlanta DayZ: vinculación y lector ADM

Esta primera etapa agrega una base aislada para vincular una cuenta Atlanta con un BI UID de Bohemia Interactive y almacenar eventos de ADM. No modifica las tablas ni las funciones existentes de perfiles, amigos, VIP o términos.

## Qué queda preparado

- Una cuenta Atlanta puede vincular un único BI UID de 44 caracteres.
- Un BI UID solo puede pertenecer a una cuenta Atlanta.
- El código de vinculación dura 10 minutos, es de un solo uso y se guarda como hash.
- El único texto que el jugador escribe en el chat es `+ATLANTA CODIGO`.
- El procesador lee ADM por SFTP y reconoce inicialmente asesinatos PvP, objetos colocados, construcciones completadas, conexiones, desconexiones, emotes, daño e inconsciencia.
- Los eventos se deduplican y los cursores se guardan en Supabase.
- Los mensajes de chat no se guardan como eventos ni se imprimen en los registros de GitHub Actions.
- El lector comienza en modo `tail`: en su primera ejecución registra el final de los ADM existentes y no importa todo el historial antiguo. Esto evita procesar años de logs por accidente.

## Paso 1: instalar la base de datos

1. Abrí Supabase del proyecto Atlanta.
2. Entrá en **SQL Editor** y creá una consulta nueva.
3. Pegá el contenido completo de `supabase/dayz-integration.sql`.
4. Ejecutalo una sola vez.
5. Si Supabase informa un error, detenete y compartí el mensaje de error sin incluir claves ni contraseñas.

## Paso 2: cargar secretos en GitHub

En el repositorio **Settings → Secrets and variables → Actions → New repository secret**, crear:

| Nombre | Contenido |
|---|---|
| `SUPABASE_URL` | URL del proyecto Supabase |
| `SUPABASE_SERVICE_ROLE_KEY` | Clave secreta service_role del proyecto |
| `DAYZ_SFTP_HOST` | Servidor SFTP de Empower |
| `DAYZ_SFTP_PORT` | Puerto SFTP (normalmente 22, confirmar con Empower) |
| `DAYZ_SFTP_USERNAME` | Usuario SFTP |
| `DAYZ_SFTP_PASSWORD` | Contraseña SFTP |
| `DAYZ_SFTP_PROFILES_PATH` | Ruta remota exacta a la carpeta profiles |
| `DAYZ_SFTP_HOST_KEY_SHA256` | Huella SHA256 de la clave SSH del servidor SFTP |

**Nunca pegues las claves, contraseña SFTP ni la service_role en el chat, en archivos del repositorio o en el frontend.** La service_role solo debe existir como secreto de Actions. Si Empower ofrece una cuenta SFTP de solo lectura, usá esa cuenta.

La huella SSH debe obtenerse de Empower o verificarse con su soporte. No uses una huella copiada de una fuente no confiable: el lector rechaza el servidor si no coincide.

## Paso 3: activar el procesador cuando esté verificado

En **Settings → Secrets and variables → Actions → Variables → New repository variable**, crear:

- Nombre: `DAYZ_INGEST_ENABLED`
- Valor: `true`

El workflow `.github/workflows/dayz-reader.yml` se programa cada 5 minutos y también permite ejecución manual. GitHub puede retrasar los horarios programados; no es un reloj exacto.

Para mantener la primera prueba controlada, dejá la variable sin crear hasta que:
- el SQL haya terminado correctamente;
- los secretos estén completos;
- la ruta remota a `profiles` sea correcta;
- la huella SSH esté verificada.

## Paso 4: generar códigos de vinculación (pendiente de interfaz)

La función `create_dayz_link_code()` ya está preparada para que la invoque la página cuando el usuario haya iniciado sesión. La interfaz todavía no se habilita en esta etapa. Primero vamos a comprobar el acceso SFTP y el formato real del chat ADM.

El código que genera es de 8 caracteres hexadecimales, vence a los 10 minutos y no puede reutilizarse. El jugador lo escribirá en el chat del servidor con el formato:

`+ATLANTA A1B2C3D4`

El lector detecta el mensaje y confirma la vinculación usando el BI UID que figura en esa misma línea del ADM.

## Paso 5: validar antes de mostrar logros

Antes de activar logros o estadísticas en la web hay que confirmar con un ADM real:
- que el mensaje de chat tiene exactamente el formato esperado;
- que el UID del chat coincide con el UID de eventos de ese jugador;
- que los archivos tienen el nombre y la fecha esperados;
- que Empower permite leer la carpeta con la cuenta SFTP configurada;
- que el horario de los ADM se interpreta correctamente.

Los tiempos se guardan inicialmente como hora local escrita en el ADM, sin inventar zona horaria.

## Alcance actual y límites conocidos

Esta entrega es la infraestructura inicial, no el sistema completo de logros. Todavía no se muestran estadísticas en `cuenta.html`, no se cargan definiciones de logros y no se activa la interfaz de vinculación. Tampoco se interpretan todavía todas las causas de muerte de DayZ; por ejemplo, la muerte por infectados requiere confirmar el formato exacto que emite el servidor.

El primer escaneo usa modo `tail`: no importa eventos anteriores al momento en que se activa el lector. Más adelante se puede hacer una importación histórica controlada si hace falta.

Si una ejecución no puede conectarse o guardar el lote, no avanza el cursor de esos datos, de modo que la siguiente ejecución puede reintentarlos. Los eventos tienen una clave idempotente para evitar duplicados.
