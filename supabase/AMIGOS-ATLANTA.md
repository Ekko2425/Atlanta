# Amigos de Atlanta DayZ

## Cambios
- Se quitaron del perfil los contadores de asesinatos, muertes y horas jugadas: SteamID64 por sí solo no entrega estadísticas del servidor Atlanta.
- El perfil muestra el SteamID64 y un enlace directo al perfil público de Steam.
- Se agregó una lista de amigos propia de Atlanta: búsqueda por nombre de jugador o SteamID64, solicitudes, aceptar, rechazar, cancelar y eliminar amigos.

## Activación de Supabase
1. Abrir el proyecto Atlanta-Community → SQL Editor → New query.
2. Copiar y ejecutar el archivo `supabase/friends.sql`.
3. Recargar `https://ekko2425.github.io/Atlanta/cuenta.html`.

La migración crea `public.friend_requests`, activa RLS, limita las solicitudes al usuario autenticado y habilita la lectura de perfiles públicos de la comunidad. No expone correos electrónicos.

## Datos de Steam
El enlace al perfil de Steam se construye desde el SteamID64. Para mostrar automáticamente el nombre y avatar de Steam dentro de Atlanta se necesita una función backend/Edge Function y una Steam Web API key guardada como secreto; nunca debe colocarse esa clave en `cuenta.html`.
La API de Steam puede devolver nombre de perfil, URL y avatares, sujetos a la privacidad del usuario. No se asume que Steam publique kills/deaths/horas de DayZ.

## Nota
Las solicitudes y amistades de Atlanta son independientes de la lista de amigos de Steam.
