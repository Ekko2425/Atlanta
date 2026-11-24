# Perfiles públicos de jugadores

## Activación
En Supabase → SQL Editor → New query, pegá el contenido de `public-player-profile.sql` y presioná **Run**.

Esto habilita la lectura pública de campos comunitarios del perfil: nombre de jugador, fecha de alta, avatar, SteamID64, descripción y rango VIP. No expone correo electrónico ni datos privados de autenticación.

## Uso
- Desde amigos, solicitudes y resultados de búsqueda, hacé clic en el nombre del jugador.
- El perfil abre en una URL compartible: `cuenta.html?profile=UUID`.
- Los visitantes pueden ver el perfil sin iniciar sesión.
