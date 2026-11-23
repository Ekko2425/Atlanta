# Perfil de jugador — Atlanta DayZ

## Qué incluye

- Nombre de jugador editable (3–20 caracteres: letras, números y guion bajo).
- Foto de perfil JPG, PNG o WebP de hasta 2 MB.
- SteamID64 opcional, validado a 17 dígitos y único.
- Descripción personal de hasta 240 caracteres.
- Rango VIP visible en la ficha.
- Estadísticas: asesinatos, muertes y horas jugadas.

## Activación obligatoria en Supabase

1. Abrí el proyecto Atlanta-Community.
2. Entrá en SQL Editor → New query.
3. Abrí `supabase/profile-upgrade.sql` en GitHub y copiá el archivo completo.
4. Pegalo en SQL Editor y ejecutá Run.
5. Verificá en Table Editor → public → profiles que existan las columnas:
   `avatar_path`, `steam_id`, `bio`, `vip_rank`, `kills`, `deaths`, `playtime_hours`.
6. En Storage debe aparecer el bucket `atlanta-avatars`.

El script es una migración para ejecutar una vez. No borra perfiles ni usuarios existentes.

## Seguridad

- RLS permanece activado en `public.profiles`.
- Los usuarios autenticados pueden leer perfiles de la comunidad.
- Cada usuario solo puede modificar su propio nombre, Steam ID, descripción y ruta de avatar.
- Los permisos SQL de actualización de `vip_rank` y estadísticas se revocan a los usuarios normales. Esos campos quedan reservados para administración confiable o una integración del servidor; nunca deben escribirse desde el navegador.
- El bucket de avatares es público para que se puedan mostrar las imágenes, pero las políticas limitan las cargas, cambios y borrados a la carpeta cuyo nombre es el UUID del usuario.
- El correo electrónico no se muestra como dato público del perfil.

## Qué no está automatizado todavía

El rango VIP y las estadísticas aparecen como “Sin VIP” / “—” hasta que un administrador o una integración confiable actualice esos campos en la base de datos. Esta entrega no se conecta al servidor DayZ ni verifica compras VIP automáticamente.

## Publicación

GitHub Pages publica `cuenta.html` automáticamente desde la rama principal. Esperá unos minutos y abrí:

https://ekko2425.github.io/Atlanta/cuenta.html

Iniciá sesión con una cuenta existente. No hace falta crear otra cuenta.
