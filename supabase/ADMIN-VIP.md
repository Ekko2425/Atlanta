# Administración VIP de Atlanta DayZ

## 1. Instalar el sistema
En Supabase, abrí **SQL Editor → New query**, copiá todo el archivo `admin-vip.sql`, pegalo y presioná **Run**.

## 2. Designar al primer administrador
1. En Supabase, abrí **Authentication → Users**.
2. Buscá tu cuenta por correo y copiá su **User UID**.
3. Volvé a **SQL Editor → New query** y ejecutá esta sentencia, reemplazando el UUID por el tuyo:

```sql
insert into public.atlanta_admins (user_id)
values ('PEGAR-ACA-TU-USER-UID');
```

No uses el correo como identificador: debe ser el UUID de Auth. No compartas ese UUID públicamente.

## 3. Usar el panel
1. Iniciá sesión en https://ekko2425.github.io/Atlanta/cuenta.html con la cuenta que designaste.
2. Debajo de tu perfil aparecerá **Administración VIP**.
3. Buscá un jugador, elegí su rango y presioná **Guardar**.

Rangos disponibles: Sin VIP, VIP Bronce, VIP Plata, VIP Oro, VIP Diamante y VIP Leyenda.

## Seguridad
- Los usuarios comunes no pueden ver el panel ni enumerar jugadores a través de las funciones administrativas.
- Las funciones del servidor verifican la tabla privada `atlanta_admins` en cada operación.
- Los jugadores no pueden modificar `vip_rank` desde el formulario de su perfil.
- Para revocar el acceso de un administrador, eliminá su fila de `public.atlanta_admins` desde SQL Editor:

```sql
delete from public.atlanta_admins
where user_id = 'USER-UID';
```

No pongas claves `service_role` en el sitio web ni en GitHub.
