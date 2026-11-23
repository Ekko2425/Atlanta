# Cuentas de la comunidad Atlanta DayZ

La interfaz de registro e inicio de sesión está en `cuenta.html`. Usa Supabase Auth para no almacenar contraseñas en el sitio estático y una tabla `profiles` protegida con Row Level Security para los nombres de jugador.

## 1. Crear el proyecto Supabase

1. Entrá en https://supabase.com/ y creá un proyecto para Atlanta DayZ.
2. Guardá la contraseña de la base de datos en un gestor seguro; no la publiques en GitHub.
3. En **Project Settings → API** (o **Data API / API Keys**, según la versión), copiá la Project URL y la clave pública **anon** o **publishable**.

## 2. Crear la tabla de perfiles

1. Abrí **SQL Editor** en el panel de Supabase.
2. Pegá y ejecutá el contenido completo de `supabase/schema.sql`.
3. La tabla permite que los miembros autenticados lean los perfiles, pero cada cuenta solo puede insertar o modificar su propio perfil. No hay roles administrativos ni privilegios de moderación en esta primera versión.

## 3. Conectar el sitio

Editá `supabase-config.js` y reemplazá:
- `https://TU-PROYECTO.supabase.co` por la Project URL.
- `TU_CLAVE_PUBLICA_ANON` por la clave pública anon/publishable.

La clave pública puede estar en el frontend únicamente porque las políticas RLS protegen los datos. **Nunca uses ni publiques la clave `service_role`, una secret key o la contraseña de la base de datos.**

## 4. Ajustes de autenticación

En **Authentication → URL Configuration**:
- Site URL: la URL pública definitiva del sitio.
- Redirect URLs: agregá la URL exacta del sitio seguida de `/cuenta.html` (por ejemplo, `https://TU-SITIO/cuenta.html`).
- Dejá habilitada la confirmación de correo electrónico para validar las cuentas.
- Configurá el proveedor de correo/SMTP antes de abrir el registro al público, para que los mensajes de confirmación y recuperación lleguen correctamente.

## 5. Publicar y probar

1. Publicá los archivos de este repositorio en el hosting habitual.
2. Abrí `/cuenta.html` por HTTPS.
3. Probá un registro con un correo real, confirmá el email, iniciá sesión, cerrá sesión y probá recuperación de contraseña.
4. Comprobá en Supabase → Table Editor → profiles que se creó el perfil y que no se puede editar el perfil de otra persona.

## Qué incluye esta primera versión

- Registro abierto con email, contraseña y nombre de jugador.
- Inicio/cierre de sesión.
- Confirmación de email y recuperación de contraseña.
- Perfil básico con nombre de jugador y correo visible para el propio usuario.
- Tabla de perfiles consultable por miembros autenticados, preparada para funciones de comunidad futuras.

## Límites deliberados de seguridad

- No se guarda ninguna contraseña en la base de perfiles ni en el código del sitio; Supabase Auth administra las credenciales.
- El navegador usa únicamente la clave pública.
- No hay panel de administración ni campo de rol editable por usuarios. Si más adelante se agregan moderadores, roles o sanciones, deben gestionarse desde un entorno confiable y con políticas RLS específicas; nunca desde un selector en el frontend.
- La conexión real no estará activa hasta crear el proyecto, ejecutar el SQL y completar `supabase-config.js`.
