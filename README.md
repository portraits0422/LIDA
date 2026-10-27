# LIDA — PWA social

Aplicación web progresiva (PWA) para Lida Comunidad, Chat, Lida Reels y Lida Plays. Identidad visual basada en el logotipo original proporcionado y la referencia negra/verde neón.

## Incluye

- Pantalla inicial de 3,6 s con el logo original y resplandor animado.
- Registro e inicio de sesión separados; validación de usuario; recuperación de contraseña cuando Supabase está configurado.
- Inicio de sesión con correo o nombre de usuario mediante la Edge Function `login-by-username` (el email no se devuelve en el lookup de username).
- Tour guiado con omitir, volver, siguiente y persistencia por cuenta.
- Lida Comunidad: feed, publicaciones de texto/imagen/vídeo, reacciones, comentarios, guardar, compartir, ocultar y reportar.
- Estados con audiencia seleccionable en la interfaz, temporizador de 24 horas y controles de lista. La autorización definitiva debe aplicarse en Supabase RLS.
- Chat con lista y filtros de conversaciones, acciones contextuales, selector de emojis por categorías/búsqueda, adjuntos, notas de voz de vista previa, personalización y paneles de llamadas.
- Lida Reels con feed, publicación de vídeo, guardados y reacciones.
- Lida Plays con catálogo, favoritos, juegos HTML5 locales jugables, y añadir enlaces de juegos externos.
- Perfil, ajustes, accesibilidad, preferencias de notificaciones, exportación de datos locales y borrado de datos de vista previa.
- Búsqueda de secciones, centro de notificaciones, estado sin conexión, aviso de instalación PWA y diseño adaptable.
- SQL inicial para perfiles, publicaciones, reacciones, estados, contactos, mensajes, llamadas, notificaciones, Reels, juegos, reportes, preferencias y RLS.

## Ejecutar localmente

Requiere Node.js 20 o superior.

```bash
npm install
npm run dev
```

Para crear la compilación:

```bash
npm run build
npm run preview
```

## Modo de vista previa vs. producción

Sin credenciales, LIDA funciona en modo de vista previa local: permite explorar la interfaz y probar varias interacciones; las cuentas de vista previa se almacenan únicamente en el navegador. No uses este modo para cuentas reales ni para publicar datos personales.

Para backend real:

1. Crea un proyecto Supabase.
2. Copia `.env.example` a `.env.local` y configura `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY`.
3. Ejecuta `supabase-schema-starter.sql` en SQL Editor y revisa todas las políticas RLS antes de publicar.
4. Despliega `supabase/functions/login-by-username` con `supabase functions deploy login-by-username` y configura secretos `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`. La clave `SERVICE_ROLE` nunca debe ponerse en variables `VITE_*` ni en el frontend.
5. Configura confirmación de correo, recuperación, SMTP y límites de autenticación en Supabase Auth.
6. Habilita Realtime en las tablas necesarias, crea políticas Storage por bucket, límites de archivos y tareas de limpieza de contenido expirado.
7. Para llamadas reales, configura señalización WebRTC y credenciales STUN/TURN seguras; WebRTC transporta el audio/vídeo, Supabase Realtime no reemplaza ese transporte.
8. Configura moderación, protección anti-spam, backups, monitorización y una revisión independiente de seguridad.

## PWA / publicación

La aplicación usa manifest, service worker, iconos y rutas relativas de Vite. Netlify puede desplegar la carpeta `dist`; `public/_redirects` permite el fallback SPA. Publica por HTTPS. En iPhone, la instalación se realiza desde Safari → Compartir → Añadir a pantalla de inicio; en Android, desde el menú de instalación del navegador cuando esté disponible.

## Estado real de las funciones

La interfaz de vista previa no simula que haya otros usuarios conectados. Las acciones locales se guardan en el navegador. Chat entre personas, notificaciones en tiempo real, permisos/audiencias server-side, expiración garantizada, almacenamiento compartido, push, cifrado de extremo a extremo, llamadas WebRTC, filtros de cámara salientes y matchmaking necesitan las integraciones, credenciales, políticas y pruebas indicadas arriba. No se debe anunciar cifrado E2E ni llamadas conectadas hasta implementar y probar esas capas.

## Pruebas previas a producción

- [ ] Registro con email confirmado y username único con carreras concurrentes.
- [ ] RLS verificada como usuario A y usuario B para cada tabla y Storage bucket.
- [ ] Expiración de estados y mensajes en servidor y limpieza programada.
- [ ] Envío/entrega/lectura/reintento de mensajes, adjuntos y reconexión.
- [ ] Llamadas con permisos, STUN/TURN, reconexión y cierre en ambos extremos.
- [ ] Push en navegadores compatibles y preferencias por categoría.
- [ ] Reproducción/carga de vídeo, límites de tamaño y dispositivos modestos.
- [ ] Instalación PWA y actualizaciones en Android, iOS y escritorio.
- [ ] Accesibilidad con teclado/lector de pantalla y movimiento reducido.
- [ ] Revisión de seguridad, política de privacidad, condiciones y canal de soporte.
