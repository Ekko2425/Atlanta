# Aceptación de Términos y Condiciones — Atlanta DayZ

## Qué implementa
- La casilla de aceptación aparece únicamente al crear una cuenta.
- No se puede enviar el formulario de registro sin marcarla.
- El navegador envía la versión `2026-11-24` como metadato de registro.
- Un trigger de Supabase valida que la aceptación y la versión estén presentes.
- Otro trigger guarda en `public.legal_acceptances` la versión aceptada y la fecha/hora del servidor.
- La tabla no es legible ni modificable desde el navegador por usuarios anónimos o autenticados.

## Activación obligatoria en Supabase
1. Entrá al proyecto Atlanta DayZ en Supabase.
2. Abrí **SQL Editor** y elegí **New query**.
3. Copiá y ejecutá el contenido completo de `terms-acceptance.sql`.
4. Si Supabase muestra que la consulta terminó correctamente, la validación queda activa.

## Verificar una aceptación (solo desde SQL Editor)
```sql
select user_id, document_type, document_version, accepted_at
from public.legal_acceptances
order by accepted_at desc;
```

La fecha se genera en Supabase. No se guarda la aceptación de cuentas creadas antes de instalar esta migración: la constancia empieza a registrarse para los nuevos registros posteriores a su activación.

## Cuando se publique una nueva versión
Hay que actualizar simultáneamente:
- La versión/fecha del documento `terminos.html`.
- La constante `TERMS_VERSION` de `cuenta.html`.
- Las dos apariciones de la versión `2026-11-24` en `terms-acceptance.sql` (validación e inserción).

Luego hay que ejecutar una migración que actualice la validación del trigger para exigir la nueva versión. No basta con cambiar el HTML.
